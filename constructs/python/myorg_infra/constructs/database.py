from __future__ import annotations
from constructs import Construct
from cdktf import TerraformModule
from dataclasses import dataclass, field
from typing import Dict, List, Optional
from ..policy.tagging import required_tags

_MODULE_SOURCE = (
    "git::ssh://git@github.com/myorg/terraform-modules.git"
    "//modules/database/postgres?ref=v1.4.0"
)


@dataclass
class PostgresConfig:
    """Optional configuration overrides for a PostgreSQL Flexible Server."""

    databases: List[str] = field(default_factory=list)
    sku: str = "GP_Standard_D2s_v3"
    storage_mb: int = 32768
    pg_version: str = "15"
    ha_enabled: bool = False
    geo_redundant: bool = False
    server_configs: Dict[str, str] = field(default_factory=dict)
    extra_tags: dict = field(default_factory=dict)


class DatabaseConstruct(Construct):
    """Provisions an Azure PostgreSQL Flexible Server with private VNet access.

    Wraps modules/database/postgres from the platform Terraform module repo.
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
        dns_zone_id: str,
        admin_password: str,
        config: Optional[PostgresConfig] = None,
    ):
        super().__init__(scope, id_)
        cfg = config or PostgresConfig()

        self._module = TerraformModule(
            self, "postgres",
            source=_MODULE_SOURCE,
            variables={
                "project":                 project,
                "environment":             environment,
                "resource_group_name":     resource_group,
                "location":                location,
                "delegated_subnet_id":     subnet_id,
                "private_dns_zone_id":     dns_zone_id,
                "administrator_password":  admin_password,
                "databases":               cfg.databases,
                "sku_name":                cfg.sku,
                "storage_mb":              cfg.storage_mb,
                "pg_version":              cfg.pg_version,
                "high_availability_mode":  "ZoneRedundant" if cfg.ha_enabled else "Disabled",
                "geo_redundant_backup":    cfg.geo_redundant,
                "server_configurations":   cfg.server_configs,
                "tags": {**required_tags(project, environment), **cfg.extra_tags},
            },
        )

    @property
    def fqdn(self) -> str:
        """FQDN for connecting to the server."""
        return self._module.get_string("fqdn")

    @property
    def server_id(self) -> str:
        return self._module.get_string("server_id")

    @property
    def server_name(self) -> str:
        return self._module.get_string("server_name")
