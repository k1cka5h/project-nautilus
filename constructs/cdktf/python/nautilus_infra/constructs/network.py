from __future__ import annotations
from constructs import Construct
from cdktf import TerraformModule
from dataclasses import dataclass, field
from typing import Dict, List, Optional
from ..policy.tagging import required_tags

_MODULE_SOURCE = (
    "git::ssh://git@github.com/nautilus/terraform-modules.git"
    "//modules/networking?ref=v1.4.0"
)


@dataclass
class SubnetDelegation:
    name: str
    service: str
    actions: List[str]


@dataclass
class SubnetConfig:
    address_prefix: str
    service_endpoints: List[str] = field(default_factory=list)
    delegation: Optional[SubnetDelegation] = None
    nsg_rules: Optional[List[dict]] = None


class NetworkConstruct(Construct):
    """Provisions a VNet with subnets, NSGs, and private DNS zones.

    Wraps modules/networking from the platform Terraform module repo.
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
        address_space: List[str],
        subnets: Dict[str, SubnetConfig] = None,
        private_dns_zones: List[str] = None,
        extra_tags: dict = None,
    ):
        super().__init__(scope, id_)

        def _serialize(cfg: SubnetConfig) -> dict:
            d: dict = {
                "address_prefix":    cfg.address_prefix,
                "service_endpoints": cfg.service_endpoints,
            }
            if cfg.delegation:
                d["delegation"] = {
                    "name":    cfg.delegation.name,
                    "service": cfg.delegation.service,
                    "actions": cfg.delegation.actions,
                }
            if cfg.nsg_rules:
                d["nsg_rules"] = cfg.nsg_rules
            return d

        self._module = TerraformModule(
            self, "networking",
            source=_MODULE_SOURCE,
            variables={
                "project":             project,
                "environment":         environment,
                "resource_group_name": resource_group,
                "location":            location,
                "address_space":       address_space,
                "subnets":             {k: _serialize(v) for k, v in (subnets or {}).items()},
                "private_dns_zones":   private_dns_zones or [],
                "tags":                {**required_tags(project, environment), **(extra_tags or {})},
            },
        )

    @property
    def vnet_id(self) -> str:
        return self._module.get_string("vnet_id")

    @property
    def vnet_name(self) -> str:
        return self._module.get_string("vnet_name")

    @property
    def subnet_ids(self) -> dict:
        """Map of subnet name → subnet resource ID."""
        return self._module.get("subnet_ids")

    @property
    def dns_zone_ids(self) -> dict:
        """Map of DNS zone name → resource ID."""
        return self._module.get("dns_zone_ids")
