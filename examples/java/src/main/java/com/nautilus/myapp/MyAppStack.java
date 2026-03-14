/**
 * myapp infrastructure stack — Java
 * ===================================
 * Equivalent to cdktf/stacks/myapp_stack.py.
 *
 * To synthesize:
 *   mvn compile
 *   ENVIRONMENT=dev DB_ADMIN_PASSWORD=... cdktf synth
 */

package com.nautilus.myapp;

import java.util.List;
import java.util.Map;

import software.constructs.Construct;
import com.hashicorp.cdktf.App;
import com.hashicorp.cdktf.TerraformOutput;
import com.hashicorp.cdktf.TerraformOutputConfig;

import com.nautilus.infra.BaseAzureStack;
import com.nautilus.infra.BaseAzureStackProps;
import com.nautilus.infra.constructs.NetworkConstruct;
import com.nautilus.infra.constructs.NetworkConstructProps;
import com.nautilus.infra.constructs.SubnetConfig;
import com.nautilus.infra.constructs.SubnetDelegation;
import com.nautilus.infra.constructs.DatabaseConstruct;
import com.nautilus.infra.constructs.DatabaseConstructProps;
import com.nautilus.infra.constructs.PostgresConfig;
import com.nautilus.infra.constructs.AksConstruct;
import com.nautilus.infra.constructs.AksConstructProps;
import com.nautilus.infra.constructs.AksConfig;
import com.nautilus.infra.constructs.NodePoolConfig;

public class MyAppStack extends BaseAzureStack {

    public MyAppStack(final Construct scope, final String id) {
        super(scope, id, BaseAzureStackProps.builder()
                .project("myapp")
                .environment(System.getenv().getOrDefault("ENVIRONMENT", "dev"))
                .location("eastus")
                .build());

        final boolean isProd = "prod".equals(getEnvironment());

        // ── 1. Networking ─────────────────────────────────────────────────────

        final NetworkConstruct network = new NetworkConstruct(this, "network",
                NetworkConstructProps.builder()
                        .project(getProject())
                        .environment(getEnvironment())
                        .resourceGroup("myapp-rg")
                        .location(getLocation())
                        .addressSpace(List.of("10.10.0.0/16"))
                        .subnets(Map.of(
                                "aks", SubnetConfig.builder()
                                        .addressPrefix("10.10.0.0/22")
                                        .serviceEndpoints(List.of("Microsoft.ContainerRegistry"))
                                        .build(),
                                "db", SubnetConfig.builder()
                                        .addressPrefix("10.10.8.0/24")
                                        .delegation(SubnetDelegation.builder()
                                                .name("postgres")
                                                .service("Microsoft.DBforPostgreSQL/flexibleServers")
                                                .actions(List.of(
                                                    "Microsoft.Network/virtualNetworks/subnets/join/action"
                                                ))
                                                .build())
                                        .build()))
                        .privateDnsZones(List.of("privatelink.postgres.database.azure.com"))
                        .build());

        // ── 2. Database ───────────────────────────────────────────────────────

        final DatabaseConstruct db = new DatabaseConstruct(this, "postgres",
                DatabaseConstructProps.builder()
                        .project(getProject())
                        .environment(getEnvironment())
                        .resourceGroup("myapp-rg")
                        .location(getLocation())
                        .subnetId(network.getSubnetIds().get("db"))
                        .dnsZoneId(network.getDnsZoneIds()
                                .get("privatelink.postgres.database.azure.com"))
                        .adminPassword(System.getenv("DB_ADMIN_PASSWORD"))
                        .config(PostgresConfig.builder()
                                .databases(List.of("appdb", "analyticsdb"))
                                .sku(isProd ? "GP_Standard_D2s_v3" : "B_Standard_B1ms")
                                .haEnabled(isProd)
                                .serverConfigs(Map.of("max_connections", "400"))
                                .build())
                        .build());

        // ── 3. Compute ────────────────────────────────────────────────────────

        final AksConstruct cluster = new AksConstruct(this, "aks",
                AksConstructProps.builder()
                        .project(getProject())
                        .environment(getEnvironment())
                        .resourceGroup("myapp-rg")
                        .location(getLocation())
                        .subnetId(network.getSubnetIds().get("aks"))
                        .logWorkspaceId(System.getenv("LOG_WORKSPACE_ID"))
                        .config(AksConfig.builder()
                                .systemNodeCount(isProd ? 3 : 1)
                                .additionalNodePools(Map.of(
                                        "workers", NodePoolConfig.builder()
                                                .vmSize("Standard_D8s_v3")
                                                .enableAutoScaling(true)
                                                .minCount(2)
                                                .maxCount(10)
                                                .labels(Map.of("workload", "app"))
                                                .build()))
                                .build())
                        .build());

        // ── Outputs ───────────────────────────────────────────────────────────

        new TerraformOutput(this, "db_fqdn",
                TerraformOutputConfig.builder().value(db.getFqdn()).build());

        new TerraformOutput(this, "cluster_id",
                TerraformOutputConfig.builder().value(cluster.getClusterId()).build());

        new TerraformOutput(this, "kubelet_identity_oid",
                TerraformOutputConfig.builder()
                        .value(cluster.getKubeletIdentityObjectId()).build());

        new TerraformOutput(this, "vnet_id",
                TerraformOutputConfig.builder().value(network.getVnetId()).build());
    }

    public static void main(final String[] args) {
        final App app = new App();
        new MyAppStack(app, "myapp-stack");
        app.synth();
    }
}
