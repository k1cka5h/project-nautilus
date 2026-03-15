"""
AksComponent — Azure Kubernetes Service cluster.

Delegates resource creation to the platform Terraform module via
pulumi-terraform-module interop. Pulumi orchestrates the call; Terraform
creates every Azure resource.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import pulumi
import pulumi_terraform_module as tfm

from ..policy.tagging import required_tags

_VALID_ENVIRONMENTS = {"dev", "staging", "prod"}
_MODULE_REPO = "git::ssh://git@github.com/nautilus/terraform-modules.git"
_MODULE_VERSION = "v1.0.0"
_AKS_SOURCE = f"{_MODULE_REPO}//modules/compute/aks?ref={_MODULE_VERSION}"


@dataclass
class NodePoolConfig:
    """Configuration for an additional AKS node pool."""

    vm_size: str = "Standard_D4s_v3"
    node_count: int = 2
    enable_auto_scaling: bool = False
    min_count: int = 1
    max_count: int = 10
    labels: Dict[str, str] = field(default_factory=dict)
    taints: List[str] = field(default_factory=list)


@dataclass
class AksConfig:
    """Optional configuration overrides for an AKS cluster."""

    kubernetes_version: str = "1.29"
    system_node_vm_size: str = "Standard_D2s_v3"
    system_node_count: int = 3
    additional_node_pools: Dict[str, NodePoolConfig] = field(default_factory=dict)
    admin_group_object_ids: List[str] = field(default_factory=list)
    service_cidr: str = "10.240.0.0/16"
    dns_service_ip: str = "10.240.0.10"
    extra_tags: dict = field(default_factory=dict)


def _serialise_node_pools(pools: Dict[str, NodePoolConfig]) -> Dict[str, Any]:
    """Convert NodePoolConfig dataclasses to the dict shape the TF module expects."""
    return {
        pool_name: {
            "vm_size":             pool.vm_size,
            "node_count":          pool.node_count,
            "enable_auto_scaling": pool.enable_auto_scaling,
            "min_count":           pool.min_count,
            "max_count":           pool.max_count,
            "labels":              pool.labels,
            "taints":              pool.taints,
        }
        for pool_name, pool in pools.items()
    }


class AksComponent(pulumi.ComponentResource):
    """Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.

    Delegates to the platform ``modules/compute/aks`` Terraform module.
    Terraform creates every Azure resource; Pulumi reads the outputs.

    Outputs:
        cluster_id:                     Resource ID of the managed cluster.
        cluster_name:                   Name of the managed cluster.
        kubelet_identity_object_id:     Object ID of the kubelet managed identity.
        cluster_identity_principal_id:  Principal ID of the cluster system-assigned identity.
    """

    cluster_id: pulumi.Output[str]
    cluster_name: pulumi.Output[str]
    kubelet_identity_object_id: pulumi.Output[str]
    cluster_identity_principal_id: pulumi.Output[str]

    def __init__(
        self,
        name: str,
        *,
        project: str,
        environment: str,
        resource_group: str,
        location: str,
        subnet_id: str,
        log_workspace_id: str,
        config: Optional[AksConfig] = None,
        opts: Optional[pulumi.ResourceOptions] = None,
    ) -> None:
        if environment not in _VALID_ENVIRONMENTS:
            raise ValueError(
                f"environment must be one of {sorted(_VALID_ENVIRONMENTS)}, got {environment!r}"
            )

        super().__init__("nautilus:containerservice:AksComponent", name, {}, opts)

        cfg = config or AksConfig()
        tags = required_tags(project, environment, cfg.extra_tags)

        mod = tfm.Module(
            f"{name}-aks",
            source=_AKS_SOURCE,
            variables={
                "project":                   project,
                "environment":               environment,
                "resource_group_name":       resource_group,
                "location":                  location,
                "subnet_id":                 subnet_id,
                "log_analytics_workspace_id": log_workspace_id,
                "kubernetes_version":        cfg.kubernetes_version,
                "system_node_vm_size":       cfg.system_node_vm_size,
                "system_node_count":         cfg.system_node_count,
                "additional_node_pools":     _serialise_node_pools(cfg.additional_node_pools),
                "admin_group_object_ids":    cfg.admin_group_object_ids,
                "service_cidr":              cfg.service_cidr,
                "dns_service_ip":            cfg.dns_service_ip,
                "tags":                      tags,
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        self.cluster_id                    = mod.get_output("cluster_id")
        self.cluster_name                  = mod.get_output("cluster_name")
        self.kubelet_identity_object_id    = mod.get_output("kubelet_identity_object_id")
        self.cluster_identity_principal_id = mod.get_output("cluster_identity_principal_id")

        self.register_outputs({
            "cluster_id":                    self.cluster_id,
            "cluster_name":                  self.cluster_name,
            "kubelet_identity_object_id":    self.kubelet_identity_object_id,
            "cluster_identity_principal_id": self.cluster_identity_principal_id,
        })
