"""
Construct unit tests — Python
==============================
Synthesizes each construct to JSON and asserts the module call is wired correctly.
Does not run Terraform or touch Azure.

Run:
    pip install -e ".[dev]"
    pytest tests/ -v
"""

import json
import pytest
from constructs import Construct
from cdktf import App, Testing, TerraformStack

from nautilus_infra import (
    BaseAzureStack,
    NetworkConstruct, SubnetConfig, SubnetDelegation,
    DatabaseConstruct, PostgresConfig,
    AksConstruct, AksConfig, NodePoolConfig,
)


class _Stack(TerraformStack):
    def __init__(self, scope: Construct):
        super().__init__(scope, "test-stack")


# ── NetworkConstruct ───────────────────────────────────────────────────────────

class TestNetworkConstruct:
    def setup_method(self):
        self.app = Testing.app()
        self.stack = _Stack(self.app)
        NetworkConstruct(
            self.stack, "net",
            project="myapp", environment="dev",
            resource_group="myapp-rg", location="eastus",
            address_space=["10.10.0.0/16"],
            subnets={
                "aks": SubnetConfig(address_prefix="10.10.0.0/22"),
                "db":  SubnetConfig(
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
        self.synth = json.loads(Testing.synth(self.stack))

    def test_module_source_is_pinned(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "networking" in k)
        assert "ref=v" in modules[key]["source"]

    def test_required_tags_injected(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "networking" in k)
        tags = modules[key]["tags"]
        assert tags["managed_by"] == "terraform"
        assert tags["project"] == "myapp"
        assert tags["environment"] == "dev"

    def test_subnets_serialized(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "networking" in k)
        subnets = modules[key]["subnets"]
        assert "aks" in subnets and "db" in subnets
        assert subnets["db"]["delegation"]["service"] == \
            "Microsoft.DBforPostgreSQL/flexibleServers"

    def test_invalid_environment_raises(self):
        app2 = Testing.app()
        stack2 = _Stack(app2)
        with pytest.raises(ValueError, match="environment must be"):
            NetworkConstruct(
                stack2, "net2",
                project="myapp", environment="uat",
                resource_group="rg", location="eastus",
                address_space=["10.0.0.0/16"],
            )


# ── DatabaseConstruct ──────────────────────────────────────────────────────────

class TestDatabaseConstruct:
    def setup_method(self):
        self.app = Testing.app()
        self.stack = _Stack(self.app)
        DatabaseConstruct(
            self.stack, "db",
            project="myapp", environment="prod",
            resource_group="myapp-rg", location="eastus",
            subnet_id="subnet-id", dns_zone_id="dns-zone-id",
            admin_password="Hunter2!",
            config=PostgresConfig(databases=["appdb"], ha_enabled=True),
        )
        self.synth = json.loads(Testing.synth(self.stack))

    def test_ha_enabled_in_prod(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "postgres" in k)
        assert modules[key]["high_availability_mode"] == "ZoneRedundant"

    def test_password_forwarded(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "postgres" in k)
        assert "administrator_password" in modules[key]

    def test_databases_forwarded(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "postgres" in k)
        assert "appdb" in modules[key]["databases"]


# ── AksConstruct ──────────────────────────────────────────────────────────────

class TestAksConstruct:
    def setup_method(self):
        self.app = Testing.app()
        self.stack = _Stack(self.app)
        AksConstruct(
            self.stack, "aks",
            project="myapp", environment="staging",
            resource_group="myapp-rg", location="eastus",
            subnet_id="subnet-id",
            log_workspace_id="/subscriptions/x/workspaces/logs",
            config=AksConfig(
                system_node_count=1,
                additional_node_pools={
                    "workers": NodePoolConfig(
                        vm_size="Standard_D8s_v3",
                        enable_auto_scaling=True,
                        min_count=2, max_count=10,
                        labels={"workload": "app"},
                    )
                },
            ),
        )
        self.synth = json.loads(Testing.synth(self.stack))

    def test_module_source_is_pinned(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "aks" in k)
        assert "ref=v" in modules[key]["source"]

    def test_node_pool_forwarded(self):
        modules = self.synth["module"]
        key = next(k for k in modules if "aks" in k)
        pools = modules[key]["additional_node_pools"]
        assert "workers" in pools
        assert pools["workers"]["enable_auto_scaling"] is True


# ── BaseAzureStack ─────────────────────────────────────────────────────────────

class TestBaseAzureStack:
    def test_backend_key(self):
        app = Testing.app()
        stack = BaseAzureStack(app, "base", project="proj", environment="dev")
        synth = json.loads(Testing.synth(stack))
        backend = synth["terraform"]["backend"]["azurerm"]
        assert backend["key"] == "proj/dev/terraform.tfstate"

    def test_invalid_environment_raises(self):
        app = Testing.app()
        with pytest.raises(ValueError):
            BaseAzureStack(app, "bad", project="proj", environment="qa")
