/**
 * myapp infrastructure stack — TypeScript
 * ========================================
 * Equivalent to cdktf/stacks/myapp_stack.py.
 *
 * To synthesize:
 *   npm install
 *   ENVIRONMENT=dev DB_ADMIN_PASSWORD=... cdktf synth
 */

import { Construct } from "constructs";
import { App, TerraformOutput } from "cdktf";
import {
  BaseAzureStack,
  BaseAzureStackProps,
  NetworkConstruct,
  SubnetConfig,
  SubnetDelegation,
  DatabaseConstruct,
  PostgresConfig,
  AksConstruct,
  AksConfig,
  NodePoolConfig,
} from "@nautilus/infra";

const ENVIRONMENT     = process.env.ENVIRONMENT ?? "dev";
const LOG_WORKSPACE_ID = process.env.LOG_WORKSPACE_ID ??
  "/subscriptions/00000000-0000-0000-0000-000000000000" +
  "/resourceGroups/platform-monitoring-rg" +
  "/providers/Microsoft.OperationalInsights/workspaces/platform-logs";


class MyAppStack extends BaseAzureStack {
  constructor(scope: Construct, id: string) {
    const props: BaseAzureStackProps = {
      project:     "myapp",
      environment: ENVIRONMENT,
      location:    "eastus",
    };
    super(scope, id, props);

    const isProd = this.environment === "prod";

    // ── 1. Networking ────────────────────────────────────────────────────────

    const network = new NetworkConstruct(this, "network", {
      project:       this.project,
      environment:   this.environment,
      resourceGroup: "myapp-rg",
      location:      this.location,
      addressSpace:  ["10.10.0.0/16"],
      subnets: {
        aks: new SubnetConfig({
          addressPrefix:    "10.10.0.0/22",
          serviceEndpoints: ["Microsoft.ContainerRegistry"],
        }),
        db: new SubnetConfig({
          addressPrefix: "10.10.8.0/24",
          delegation: new SubnetDelegation({
            name:    "postgres",
            service: "Microsoft.DBforPostgreSQL/flexibleServers",
            actions: ["Microsoft.Network/virtualNetworks/subnets/join/action"],
          }),
        }),
      },
      privateDnsZones: ["privatelink.postgres.database.azure.com"],
    });

    // ── 2. Database ──────────────────────────────────────────────────────────

    const db = new DatabaseConstruct(this, "postgres", {
      project:       this.project,
      environment:   this.environment,
      resourceGroup: "myapp-rg",
      location:      this.location,
      subnetId:      network.subnetIds["db"],
      dnsZoneId:     network.dnsZoneIds["privatelink.postgres.database.azure.com"],
      adminPassword: process.env.DB_ADMIN_PASSWORD!,
      config: new PostgresConfig({
        databases:     ["appdb", "analyticsdb"],
        sku:           isProd ? "GP_Standard_D2s_v3" : "B_Standard_B1ms",
        haEnabled:     isProd,
        serverConfigs: { max_connections: "400" },
      }),
    });

    // ── 3. Compute ───────────────────────────────────────────────────────────

    const cluster = new AksConstruct(this, "aks", {
      project:        this.project,
      environment:    this.environment,
      resourceGroup:  "myapp-rg",
      location:       this.location,
      subnetId:       network.subnetIds["aks"],
      logWorkspaceId: LOG_WORKSPACE_ID,
      config: new AksConfig({
        systemNodeCount: isProd ? 3 : 1,
        additionalNodePools: {
          workers: new NodePoolConfig({
            vmSize:            "Standard_D8s_v3",
            enableAutoScaling: true,
            minCount:          2,
            maxCount:          10,
            labels:            { workload: "app" },
          }),
        },
      }),
    });

    // ── Outputs ──────────────────────────────────────────────────────────────

    new TerraformOutput(this, "db_fqdn",            { value: db.fqdn });
    new TerraformOutput(this, "cluster_id",          { value: cluster.clusterId });
    new TerraformOutput(this, "kubelet_identity_oid",{ value: cluster.kubeletIdentityObjectId });
    new TerraformOutput(this, "vnet_id",             { value: network.vnetId });
  }
}


const app = new App();
new MyAppStack(app, "myapp-stack");
app.synth();
