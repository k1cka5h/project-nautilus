"""
NetworkComponent — Azure VNet, subnets, NSGs, and private DNS zones.

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
_NETWORK_SOURCE = f"{_MODULE_REPO}//modules/networking?ref={_MODULE_VERSION}"


@dataclass
class SubnetDelegation:
    """Service delegation attached to a subnet."""
    name: str
    service: str
    actions: List[str]


@dataclass
class SubnetConfig:
    """Configuration for a single subnet within the VNet."""
    address_prefix: str
    service_endpoints: List[str] = field(default_factory=list)
    delegation: Optional[SubnetDelegation] = None
    nsg_rules: Optional[List[dict]] = None


def _serialise_subnets(subnets: Dict[str, SubnetConfig]) -> Dict[str, Any]:
    """Convert SubnetConfig dataclasses to the dict shape the TF module expects."""
    result: Dict[str, Any] = {}
    for name, cfg in subnets.items():
        entry: Dict[str, Any] = {"address_prefix": cfg.address_prefix}
        if cfg.service_endpoints:
            entry["service_endpoints"] = cfg.service_endpoints
        if cfg.delegation:
            entry["delegation"] = {
                "name":    cfg.delegation.name,
                "service": cfg.delegation.service,
                "actions": cfg.delegation.actions,
            }
        if cfg.nsg_rules:
            entry["nsg_rules"] = cfg.nsg_rules
        result[name] = entry
    return result


class NetworkComponent(pulumi.ComponentResource):
    """Provisions a VNet with subnets, NSGs, and private DNS zones.

    Delegates to the platform ``modules/networking`` Terraform module.
    Terraform creates every Azure resource; Pulumi reads the outputs.

    Outputs:
        vnet_id:      Resource ID of the VNet.
        vnet_name:    Name of the VNet.
        subnet_ids:   Map of subnet name → resource ID.
        dns_zone_ids: Map of DNS zone name → resource ID.
    """

    vnet_id: pulumi.Output[str]
    vnet_name: pulumi.Output[str]
    subnet_ids: pulumi.Output[Dict[str, str]]
    dns_zone_ids: pulumi.Output[Dict[str, str]]

    def __init__(
        self,
        name: str,
        *,
        project: str,
        environment: str,
        resource_group: str,
        location: str,
        address_space: List[str],
        subnets: Optional[Dict[str, SubnetConfig]] = None,
        private_dns_zones: Optional[List[str]] = None,
        extra_tags: Optional[dict] = None,
        opts: Optional[pulumi.ResourceOptions] = None,
    ) -> None:
        if environment not in _VALID_ENVIRONMENTS:
            raise ValueError(
                f"environment must be one of {sorted(_VALID_ENVIRONMENTS)}, got {environment!r}"
            )

        super().__init__("nautilus:network:NetworkComponent", name, {}, opts)

        tags = required_tags(project, environment, extra_tags)

        mod = tfm.Module(
            f"{name}-networking",
            source=_NETWORK_SOURCE,
            variables={
                "project":              project,
                "environment":          environment,
                "resource_group_name":  resource_group,
                "location":             location,
                "address_space":        address_space,
                "subnets":              _serialise_subnets(subnets or {}),
                "private_dns_zones":    private_dns_zones or [],
                "tags":                 tags,
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        self.vnet_id     = mod.get_output("vnet_id")
        self.vnet_name   = mod.get_output("vnet_name")
        self.subnet_ids  = mod.get_output("subnet_ids")
        self.dns_zone_ids = mod.get_output("dns_zone_ids")

        self.register_outputs({
            "vnet_id":      self.vnet_id,
            "vnet_name":    self.vnet_name,
            "subnet_ids":   self.subnet_ids,
            "dns_zone_ids": self.dns_zone_ids,
        })
