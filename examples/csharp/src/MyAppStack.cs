/**
 * myapp infrastructure stack — C#
 * =================================
 * Equivalent to cdktf/stacks/myapp_stack.py.
 *
 * To synthesize:
 *   dotnet restore
 *   ENVIRONMENT=dev DB_ADMIN_PASSWORD=... cdktf synth
 */

using System;
using System.Collections.Generic;
using Constructs;
using HashiCorp.Cdktf;
using K1cka5h.Infra;
using K1cka5h.Infra.Constructs;

namespace MyApp.Infra;

class MyAppStack : BaseAzureStack
{
    public MyAppStack(Construct scope, string id)
        : base(scope, id, new BaseAzureStackProps
        {
            Project     = "myapp",
            Environment = Environment.GetEnvironmentVariable("ENVIRONMENT") ?? "dev",
            Location    = "eastus",
        })
    {
        var isProd = Environment == "prod";

        // ── 1. Networking ─────────────────────────────────────────────────────

        var network = new NetworkConstruct(this, "network", new NetworkConstructProps
        {
            Project       = Project,
            Environment   = Environment,
            ResourceGroup = "myapp-rg",
            Location      = Location,
            AddressSpace  = ["10.10.0.0/16"],
            Subnets = new Dictionary<string, SubnetConfig>
            {
                ["aks"] = new SubnetConfig
                {
                    AddressPrefix    = "10.10.0.0/22",
                    ServiceEndpoints = ["Microsoft.ContainerRegistry"],
                },
                ["db"] = new SubnetConfig
                {
                    AddressPrefix = "10.10.8.0/24",
                    Delegation = new SubnetDelegation
                    {
                        Name    = "postgres",
                        Service = "Microsoft.DBforPostgreSQL/flexibleServers",
                        Actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"],
                    },
                },
            },
            PrivateDnsZones = ["privatelink.postgres.database.azure.com"],
        });

        // ── 2. Database ───────────────────────────────────────────────────────

        var db = new DatabaseConstruct(this, "postgres", new DatabaseConstructProps
        {
            Project       = Project,
            Environment   = Environment,
            ResourceGroup = "myapp-rg",
            Location      = Location,
            SubnetId      = network.SubnetIds["db"],
            DnsZoneId     = network.DnsZoneIds["privatelink.postgres.database.azure.com"],
            AdminPassword = Environment.GetEnvironmentVariable("DB_ADMIN_PASSWORD")!,
            Config = new PostgresConfig
            {
                Databases     = ["appdb", "analyticsdb"],
                Sku           = isProd ? "GP_Standard_D2s_v3" : "B_Standard_B1ms",
                HaEnabled     = isProd,
                ServerConfigs = new Dictionary<string, string>
                {
                    ["max_connections"] = "400",
                },
            },
        });

        // ── 3. Compute ────────────────────────────────────────────────────────

        var cluster = new AksConstruct(this, "aks", new AksConstructProps
        {
            Project        = Project,
            Environment    = Environment,
            ResourceGroup  = "myapp-rg",
            Location       = Location,
            SubnetId       = network.SubnetIds["aks"],
            LogWorkspaceId = Environment.GetEnvironmentVariable("LOG_WORKSPACE_ID")!,
            Config = new AksConfig
            {
                SystemNodeCount = isProd ? 3 : 1,
                AdditionalNodePools = new Dictionary<string, NodePoolConfig>
                {
                    ["workers"] = new NodePoolConfig
                    {
                        VmSize            = "Standard_D8s_v3",
                        EnableAutoScaling = true,
                        MinCount          = 2,
                        MaxCount          = 10,
                        Labels            = new Dictionary<string, string>
                        {
                            ["workload"] = "app",
                        },
                    },
                },
            },
        });

        // ── Outputs ───────────────────────────────────────────────────────────

        new TerraformOutput(this, "db_fqdn",
            new TerraformOutputConfig { Value = db.Fqdn });

        new TerraformOutput(this, "cluster_id",
            new TerraformOutputConfig { Value = cluster.ClusterId });

        new TerraformOutput(this, "kubelet_identity_oid",
            new TerraformOutputConfig { Value = cluster.KubeletIdentityObjectId });

        new TerraformOutput(this, "vnet_id",
            new TerraformOutputConfig { Value = network.VnetId });
    }
}


class Program
{
    static void Main()
    {
        var app = new App();
        new MyAppStack(app, "myapp-stack");
        app.Synth();
    }
}
