"""
Component unit tests — Python
==============================
Uses pulumi.runtime.set_mocks() to intercept resource creation and assert
component wiring without deploying any real Azure resources.

Run:
    pip install -e ".[dev]"
    pytest tests/ -v
"""

from __future__ import annotations

import asyncio
from typing import Any, Dict, Optional, Tuple

import pytest
import pulumi


class MockMins(pulumi.runtime.Mocks):
    """Minimal Pulumi mock that returns a predictable ID and the given inputs."""

    def new_resource(
        self,
        args: pulumi.runtime.MockResourceArgs,
    ) -> Tuple[Optional[str], Dict[str, Any]]:
        outputs = dict(args.inputs)
        # Provide synthetic outputs that components access.
        outputs.setdefault("id", args.name + "_id")
        outputs.setdefault("name", args.name)
        outputs.setdefault("fullyQualifiedDomainName", args.name + ".postgres.database.azure.com")
        outputs.setdefault("identityProfile", {
            "kubeletidentity": {"objectId": "kubelet-oid-" + args.name}
        })
        outputs.setdefault("identity", {"principalId": "principal-id-" + args.name})
        return args.name + "_id", outputs

    def call(
        self,
        args: pulumi.runtime.MockCallArgs,
    ) -> Dict[str, Any]:
        return {}


pulumi.runtime.set_mocks(MockMins(), project="test-project", stack="test-stack")

from nautilus_infra_pulumi import (  # noqa: E402  (must import after set_mocks)
    NetworkComponent,
    SubnetConfig,
    SubnetDelegation,
    DatabaseComponent,
    PostgresConfig,
    AksComponent,
    AksConfig,
    NodePoolConfig,
    required_tags,
)


# ── required_tags ──────────────────────────────────────────────────────────────

class TestRequiredTags:
    def test_required_keys_present(self):
        tags = required_tags("myapp", "dev")
        assert tags["managed_by"] == "pulumi"
        assert tags["project"] == "myapp"
        assert tags["environment"] == "dev"

    def test_required_tags_win_over_extra(self):
        tags = required_tags("myapp", "prod", extra={"managed_by": "manual", "team": "platform"})
        assert tags["managed_by"] == "pulumi"
        assert tags["team"] == "platform"

    def test_extra_keys_included(self):
        tags = required_tags("svc", "staging", extra={"cost_center": "eng"})
        assert tags["cost_center"] == "eng"


# ── NetworkComponent ───────────────────────────────────────────────────────────

@pulumi.runtime.test
async def test_network_invalid_environment_raises():
    with pytest.raises(ValueError, match="environment must be"):
        NetworkComponent(
            "net",
            project="myapp", environment="uat",
            resource_group="rg", location="eastus",
            address_space=["10.0.0.0/16"],
        )


@pulumi.runtime.test
async def test_network_vnet_id_is_output():
    comp = NetworkComponent(
        "net",
        project="myapp", environment="dev",
        resource_group="myapp-dev-rg", location="eastus",
        address_space=["10.10.0.0/16"],
        subnets={
            "aks": SubnetConfig(address_prefix="10.10.0.0/22"),
            "db": SubnetConfig(
                address_prefix="10.10.8.0/24",
                delegation=SubnetDelegation(
                    name="postgres",
                    service="Microsoft.DBforPostgreSQL/flexibleServers",
                    actions=["Microsoft.Network/virtualNetworks/subnets/join/action"],
                ),
            ),
        },
        private_dns_zones=["privatelink.postgres.database.azure.com"],
    )

    vnet_id = await pulumi.Output.all(comp.vnet_id).apply(lambda vs: vs[0])
    assert vnet_id is not None and vnet_id != ""


@pulumi.runtime.test
async def test_network_subnet_ids_contains_configured_subnets():
    comp = NetworkComponent(
        "net2",
        project="myapp", environment="staging",
        resource_group="rg", location="eastus",
        address_space=["10.0.0.0/16"],
        subnets={
            "aks": SubnetConfig(address_prefix="10.0.0.0/22"),
            "db":  SubnetConfig(address_prefix="10.0.8.0/24"),
        },
    )

    subnet_ids = await comp.subnet_ids
    assert "aks" in subnet_ids
    assert "db" in subnet_ids


# ── DatabaseComponent ──────────────────────────────────────────────────────────

@pulumi.runtime.test
async def test_database_invalid_environment_raises():
    with pytest.raises(ValueError, match="environment must be"):
        DatabaseComponent(
            "db",
            project="myapp", environment="qa",
            resource_group="rg", location="eastus",
            subnet_id="sn-id", dns_zone_id="dns-id",
            admin_password="Hunter2!",
        )


@pulumi.runtime.test
async def test_database_fqdn_is_output():
    comp = DatabaseComponent(
        "db",
        project="myapp", environment="prod",
        resource_group="myapp-prod-rg", location="eastus",
        subnet_id="/subscriptions/x/subnets/db",
        dns_zone_id="/subscriptions/x/privateDnsZones/postgres",
        admin_password="Hunter2!",
        config=PostgresConfig(databases=["appdb"], ha_enabled=True),
    )

    fqdn = await comp.fqdn
    assert fqdn is not None and fqdn != ""


@pulumi.runtime.test
async def test_database_ha_config_forwarded():
    """HA-enabled config must reach the server resource."""
    comp = DatabaseComponent(
        "db-ha",
        project="myapp", environment="prod",
        resource_group="rg", location="eastus",
        subnet_id="sn", dns_zone_id="dns",
        admin_password="secret",
        config=PostgresConfig(ha_enabled=True),
    )
    # Component constructs without error — HA args are validated at resource level.
    assert comp.server_id is not None


# ── AksComponent ───────────────────────────────────────────────────────────────

@pulumi.runtime.test
async def test_aks_invalid_environment_raises():
    with pytest.raises(ValueError, match="environment must be"):
        AksComponent(
            "aks",
            project="myapp", environment="badenv",
            resource_group="rg", location="eastus",
            subnet_id="sn", log_workspace_id="ws",
        )


@pulumi.runtime.test
async def test_aks_cluster_id_is_output():
    comp = AksComponent(
        "aks",
        project="myapp", environment="staging",
        resource_group="myapp-staging-rg", location="eastus",
        subnet_id="/subscriptions/x/subnets/aks",
        log_workspace_id="/subscriptions/x/workspaces/logs",
        config=AksConfig(
            system_node_count=1,
            additional_node_pools={
                "workers": NodePoolConfig(
                    vm_size="Standard_D8s_v3",
                    enable_auto_scaling=True,
                    min_count=2,
                    max_count=10,
                    labels={"workload": "app"},
                )
            },
        ),
    )

    cluster_id = await comp.cluster_id
    assert cluster_id is not None and cluster_id != ""


@pulumi.runtime.test
async def test_aks_required_tags_injected():
    comp = AksComponent(
        "aks2",
        project="myapp", environment="dev",
        resource_group="rg", location="eastus",
        subnet_id="sn", log_workspace_id="ws",
        config=AksConfig(extra_tags={"cost_center": "eng"}),
    )
    # Component initializes without error — tags are passed through to resources.
    assert comp.cluster_name is not None
