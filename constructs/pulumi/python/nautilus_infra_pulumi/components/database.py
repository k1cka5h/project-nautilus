"""
DatabaseComponent — Azure PostgreSQL Flexible Server with VNet integration.

Delegates resource creation to the platform Terraform module via
pulumi-terraform-module interop. Pulumi orchestrates the call; Terraform
creates every Azure resource.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

import pulumi
import pulumi_terraform_module as tfm

from ..policy.tagging import required_tags

_VALID_ENVIRONMENTS = {"dev", "staging", "prod"}
_MODULE_REPO = "git::ssh://git@github.com/nautilus/terraform-modules.git"
_MODULE_VERSION = "v1.0.0"
_POSTGRES_SOURCE = f"{_MODULE_REPO}//modules/database/postgres?ref={_MODULE_VERSION}"


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


class DatabaseComponent(pulumi.ComponentResource):
    """Provisions an Azure PostgreSQL Flexible Server with private VNet access.

    Delegates to the platform ``modules/database/postgres`` Terraform module.
    Terraform creates every Azure resource; Pulumi reads the outputs.

    Outputs:
        fqdn:        Fully-qualified domain name for client connections.
        server_id:   Resource ID of the flexible server.
        server_name: Name of the flexible server.
    """

    fqdn: pulumi.Output[str]
    server_id: pulumi.Output[str]
    server_name: pulumi.Output[str]

    def __init__(
        self,
        name: str,
        *,
        project: str,
        environment: str,
        resource_group: str,
        location: str,
        subnet_id: str,
        dns_zone_id: str,
        admin_password: str,
        config: Optional[PostgresConfig] = None,
        opts: Optional[pulumi.ResourceOptions] = None,
    ) -> None:
        if environment not in _VALID_ENVIRONMENTS:
            raise ValueError(
                f"environment must be one of {sorted(_VALID_ENVIRONMENTS)}, got {environment!r}"
            )

        super().__init__("nautilus:database:DatabaseComponent", name, {}, opts)

        cfg = config or PostgresConfig()
        tags = required_tags(project, environment, cfg.extra_tags)

        mod = tfm.Module(
            f"{name}-postgres",
            source=_POSTGRES_SOURCE,
            variables={
                "project":                    project,
                "environment":                environment,
                "resource_group_name":        resource_group,
                "location":                   location,
                "delegated_subnet_id":        subnet_id,
                "private_dns_zone_id":        dns_zone_id,
                "administrator_password":     admin_password,
                "databases":                  cfg.databases,
                "sku_name":                   cfg.sku,
                "storage_mb":                 cfg.storage_mb,
                "pg_version":                 cfg.pg_version,
                "high_availability_mode":     "ZoneRedundant" if cfg.ha_enabled else "Disabled",
                "geo_redundant_backup":       cfg.geo_redundant,
                "server_configurations":      cfg.server_configs,
                "tags":                       tags,
            },
            opts=pulumi.ResourceOptions(parent=self),
        )

        self.fqdn        = mod.get_output("fqdn")
        self.server_id   = mod.get_output("server_id")
        self.server_name = mod.get_output("server_name")

        self.register_outputs({
            "fqdn":        self.fqdn,
            "server_id":   self.server_id,
            "server_name": self.server_name,
        })
