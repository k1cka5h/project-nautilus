from __future__ import annotations
from constructs import Construct
from cdktf import TerraformModule
from dataclasses import dataclass, field
from typing import Dict, List, Optional
from ..policy.tagging import required_tags

_MODULE_SOURCE = (
    "git::ssh://git@github.com/nautilus/terraform-modules.git"
    "//modules/compute/aks?ref=v1.4.0"
)


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


class AksConstruct(Construct):
    """Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.

    Wraps modules/compute/aks from the platform Terraform module repo.
    """

    def __init__(
        self,
        scope: Construct,
        id_: str,
        *,
        project: str,
        environment: str,
        resource_group: str,
        location: str,
        subnet_id: str,
        log_workspace_id: str,
        config: Optional[AksConfig] = None,
    ):
        super().__init__(scope, id_)
        cfg = config or AksConfig()

        self._module = TerraformModule(
            self, "aks",
            source=_MODULE_SOURCE,
            variables={
                "project":                    project,
                "environment":                environment,
                "resource_group_name":        resource_group,
                "location":                   location,
                "subnet_id":                  subnet_id,
                "log_analytics_workspace_id": log_workspace_id,
                "kubernetes_version":         cfg.kubernetes_version,
                "system_node_vm_size":        cfg.system_node_vm_size,
                "system_node_count":          cfg.system_node_count,
                "additional_node_pools": {
                    k: {
                        "vm_size":             v.vm_size,
                        "node_count":          v.node_count,
                        "enable_auto_scaling": v.enable_auto_scaling,
                        "min_count":           v.min_count,
                        "max_count":           v.max_count,
                        "labels":              v.labels,
                        "taints":              v.taints,
                    }
                    for k, v in cfg.additional_node_pools.items()
                },
                "admin_group_object_ids": cfg.admin_group_object_ids,
                "service_cidr":           cfg.service_cidr,
                "dns_service_ip":         cfg.dns_service_ip,
                "tags": {**required_tags(project, environment), **cfg.extra_tags},
            },
        )

    @property
    def cluster_id(self) -> str:
        return self._module.get_string("cluster_id")

    @property
    def cluster_name(self) -> str:
        return self._module.get_string("cluster_name")

    @property
    def kubelet_identity_object_id(self) -> str:
        """Assign ACR pull and Key Vault read to this identity."""
        return self._module.get_string("kubelet_identity_object_id")

    @property
    def cluster_identity_principal_id(self) -> str:
        """Assign Network Contributor to this identity."""
        return self._module.get_string("cluster_identity_principal_id")
