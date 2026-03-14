"""
myapp infrastructure stack — Python
=====================================
Equivalent to all other examples in examples/<language>/.

To synthesize:
    pip install k1cka5h-infra==1.4.0 --index-url https://pkgs.k1cka5h.internal/simple
    npm install -g cdktf-cli@0.20
    ENVIRONMENT=dev DB_ADMIN_PASSWORD=... cdktf synth
"""

import os
from constructs import Construct
from cdktf import App, TerraformOutput

from k1cka5h_infra import (
    BaseAzureStack,
    NetworkConstruct,
    SubnetConfig,
    SubnetDelegation,
    DatabaseConstruct,
    PostgresConfig,
    AksConstruct,
    AksConfig,
    NodePoolConfig,
)

ENVIRONMENT      = os.environ["ENVIRONMENT"]
LOG_WORKSPACE_ID = os.environ.get(
    "LOG_WORKSPACE_ID",
    "/subscriptions/00000000-0000-0000-0000-000000000000"
    "/resourceGroups/platform-monitoring-rg"
    "/providers/Microsoft.OperationalInsights/workspaces/platform-logs",
)


class MyAppStack(BaseAzureStack):
    def __init__(self, scope: Construct, id_: str):
        super().__init__(
            scope, id_,
            project="myapp",
            environment=ENVIRONMENT,
            location="eastus",
        )

        is_prod = self.environment == "prod"

        # ── 1. Networking ─────────────────────────────────────────────────────

        network = NetworkConstruct(
            self, "network",
            project=self.project,
            environment=self.environment,
            resource_group="myapp-rg",
            location=self.location,
            address_space=["10.10.0.0/16"],
            subnets={
                "aks": SubnetConfig(
                    address_prefix="10.10.0.0/22",
                    service_endpoints=["Microsoft.ContainerRegistry"],
                ),
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

        # ── 2. Database ───────────────────────────────────────────────────────

        db = DatabaseConstruct(
            self, "postgres",
            project=self.project,
            environment=self.environment,
            resource_group="myapp-rg",
            location=self.location,
            subnet_id=network.subnet_ids["db"],
            dns_zone_id=network.dns_zone_ids["privatelink.postgres.database.azure.com"],
            admin_password=os.environ["DB_ADMIN_PASSWORD"],
            config=PostgresConfig(
                databases=["appdb", "analyticsdb"],
                sku="B_Standard_B1ms" if not is_prod else "GP_Standard_D2s_v3",
                ha_enabled=is_prod,
                server_configs={"max_connections": "400"},
            ),
        )

        # ── 3. Compute ────────────────────────────────────────────────────────

        cluster = AksConstruct(
            self, "aks",
            project=self.project,
            environment=self.environment,
            resource_group="myapp-rg",
            location=self.location,
            subnet_id=network.subnet_ids["aks"],
            log_workspace_id=LOG_WORKSPACE_ID,
            config=AksConfig(
                system_node_count=3 if is_prod else 1,
                additional_node_pools={
                    "workers": NodePoolConfig(
                        vm_size="Standard_D8s_v3",
                        enable_auto_scaling=True,
                        min_count=2,
                        max_count=10,
                        labels={"workload": "app"},
                    ),
                },
            ),
        )

        # ── Outputs ───────────────────────────────────────────────────────────

        TerraformOutput(self, "db_fqdn",             value=db.fqdn)
        TerraformOutput(self, "cluster_id",          value=cluster.cluster_id)
        TerraformOutput(self, "kubelet_identity_oid",value=cluster.kubelet_identity_object_id)
        TerraformOutput(self, "vnet_id",             value=network.vnet_id)


app = App()
MyAppStack(app, "myapp-stack")
app.synth()
