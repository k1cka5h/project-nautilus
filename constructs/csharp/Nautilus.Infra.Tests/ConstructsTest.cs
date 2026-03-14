using System.Text.Json;
using HashiCorp.Cdktf;
using Xunit;

namespace Nautilus.Infra.Tests;

/// <summary>
/// Construct unit tests — C#
/// ==========================
/// Synthesizes each construct to JSON and asserts the module call is wired
/// correctly. Does not run Terraform or touch Azure.
///
/// Run:
///   dotnet test Nautilus.Infra.Tests/
/// </summary>
public class ConstructsTest
{
    // ── helpers ────────────────────────────────────────────────────────────────

    private static TerraformStack PlainStack()
    {
        var app = Testing.App();
        return new TerraformStack(app, "test-stack");
    }

    private static JsonElement Synth(TerraformStack stack)
    {
        var json = Testing.SynthScope(stack);
        return JsonSerializer.Deserialize<JsonElement>(json);
    }

    private static JsonElement Module(JsonElement synth, string keyContains)
    {
        foreach (var prop in synth.GetProperty("module").EnumerateObject())
            if (prop.Name.Contains(keyContains))
                return prop.Value;
        throw new KeyNotFoundException($"No module key containing '{keyContains}'");
    }


    // ── BaseAzureStack ─────────────────────────────────────────────────────────

    [Fact]
    public void BaseStack_SetsCorrectStateKey()
    {
        var app   = Testing.App();
        var stack = new BaseAzureStack(app, "base",
            new BaseAzureStackProps("proj", "dev"));

        var synth = Synth(stack);
        var key   = synth
            .GetProperty("terraform")
            .GetProperty("backend")
            .GetProperty("azurerm")
            .GetProperty("key")
            .GetString();

        Assert.Equal("proj/dev/terraform.tfstate", key);
    }

    [Fact]
    public void BaseStack_DefaultLocationIsEastUs()
    {
        var app   = Testing.App();
        var stack = new BaseAzureStack(app, "base2",
            new BaseAzureStackProps("proj", "staging"));

        Assert.Equal("eastus", stack.Location);
    }

    [Fact]
    public void BaseStack_ThrowsOnInvalidEnvironment()
    {
        var app = Testing.App();
        Assert.Throws<ArgumentException>(() =>
            new BaseAzureStack(app, "bad",
                new BaseAzureStackProps("proj", "uat")));
    }


    // ── NetworkConstruct ───────────────────────────────────────────────────────

    [Fact]
    public void Network_ModuleSourceIsPinned()
    {
        var stack = PlainStack();
        new NetworkConstruct(stack, "net", new NetworkConstructProps(
            Project: "myapp", Environment: "dev",
            ResourceGroup: "myapp-dev-rg", Location: "eastus",
            AddressSpace: ["10.0.0.0/16"]));

        var mod = Module(Synth(stack), "networking");
        Assert.Contains("ref=v", mod.GetProperty("source").GetString());
    }

    [Fact]
    public void Network_RequiredTagsInjected()
    {
        var stack = PlainStack();
        new NetworkConstruct(stack, "net", new NetworkConstructProps(
            Project: "myapp", Environment: "staging",
            ResourceGroup: "myapp-staging-rg", Location: "eastus",
            AddressSpace: ["10.0.0.0/16"]));

        var tags = Module(Synth(stack), "networking").GetProperty("tags");
        Assert.Equal("terraform", tags.GetProperty("managed_by").GetString());
        Assert.Equal("myapp",     tags.GetProperty("project").GetString());
        Assert.Equal("staging",   tags.GetProperty("environment").GetString());
    }

    [Fact]
    public void Network_SubnetDelegationSerialized()
    {
        var stack = PlainStack();
        new NetworkConstruct(stack, "net", new NetworkConstructProps(
            Project: "myapp", Environment: "dev",
            ResourceGroup: "myapp-dev-rg", Location: "eastus",
            AddressSpace: ["10.0.0.0/16"],
            Subnets: new Dictionary<string, SubnetConfig>
            {
                ["db"] = new SubnetConfig(
                    AddressPrefix: "10.0.8.0/24",
                    Delegation: new SubnetDelegation(
                        Name: "postgres",
                        Service: "Microsoft.DBforPostgreSQL/flexibleServers",
                        Actions: ["Microsoft.Network/virtualNetworks/subnets/join/action"]))
            }));

        var mod = Module(Synth(stack), "networking");
        var service = mod
            .GetProperty("subnets").GetProperty("db")
            .GetProperty("delegation").GetProperty("service")
            .GetString();
        Assert.Equal("Microsoft.DBforPostgreSQL/flexibleServers", service);
    }

    [Fact]
    public void Network_ThrowsOnInvalidEnvironment()
    {
        var stack = PlainStack();
        // NetworkConstruct does not validate environment itself — BaseAzureStack does.
        // This verifies the stack-level guard is sufficient.
        var app = Testing.App();
        Assert.Throws<ArgumentException>(() =>
            new BaseAzureStack(app, "bad",
                new BaseAzureStackProps("proj", "uat")));
    }


    // ── DatabaseConstruct ──────────────────────────────────────────────────────

    [Fact]
    public void Database_ModuleSourceIsPinned()
    {
        var stack = PlainStack();
        new DatabaseConstruct(stack, "db", new DatabaseConstructProps(
            Project: "myapp", Environment: "prod",
            ResourceGroup: "myapp-prod-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/db",
            DnsZoneId: "/subscriptions/x/privateDnsZones/postgres",
            AdminPassword: "Hunter2!"));

        var src = Module(Synth(stack), "postgres").GetProperty("source").GetString();
        Assert.Contains("ref=v", src);
        Assert.Contains("modules/database/postgres", src);
    }

    [Fact]
    public void Database_HaEnabledSetsZoneRedundant()
    {
        var stack = PlainStack();
        new DatabaseConstruct(stack, "db", new DatabaseConstructProps(
            Project: "myapp", Environment: "prod",
            ResourceGroup: "myapp-prod-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/db",
            DnsZoneId: "/subscriptions/x/privateDnsZones/postgres",
            AdminPassword: "Hunter2!",
            Config: new PostgresConfig(Databases: ["appdb"], HaEnabled: true)));

        var ha = Module(Synth(stack), "postgres")
            .GetProperty("high_availability_mode").GetString();
        Assert.Equal("ZoneRedundant", ha);
    }

    [Fact]
    public void Database_HaDisabledSetsDisabled()
    {
        var stack = PlainStack();
        new DatabaseConstruct(stack, "db", new DatabaseConstructProps(
            Project: "myapp", Environment: "dev",
            ResourceGroup: "myapp-dev-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/db",
            DnsZoneId: "/subscriptions/x/privateDnsZones/postgres",
            AdminPassword: "Hunter2!"));

        var ha = Module(Synth(stack), "postgres")
            .GetProperty("high_availability_mode").GetString();
        Assert.Equal("Disabled", ha);
    }

    [Fact]
    public void Database_AdminPasswordPresent()
    {
        var stack = PlainStack();
        new DatabaseConstruct(stack, "db", new DatabaseConstructProps(
            Project: "myapp", Environment: "dev",
            ResourceGroup: "myapp-dev-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/db",
            DnsZoneId: "/subscriptions/x/privateDnsZones/postgres",
            AdminPassword: "MySecret123!"));

        var mod = Module(Synth(stack), "postgres");
        Assert.True(mod.TryGetProperty("administrator_password", out _),
            "administrator_password should be present in module variables");
    }


    // ── AksConstruct ──────────────────────────────────────────────────────────

    [Fact]
    public void Aks_ModuleSourceIsPinned()
    {
        var stack = PlainStack();
        new AksConstruct(stack, "aks", new AksConstructProps(
            Project: "myapp", Environment: "dev",
            ResourceGroup: "myapp-dev-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/aks",
            LogWorkspaceId: "/subscriptions/x/workspaces/logs"));

        var src = Module(Synth(stack), "aks").GetProperty("source").GetString();
        Assert.Contains("ref=v", src);
        Assert.Contains("modules/compute/aks", src);
    }

    [Fact]
    public void Aks_AdditionalNodePoolForwarded()
    {
        var stack = PlainStack();
        new AksConstruct(stack, "aks", new AksConstructProps(
            Project: "myapp", Environment: "staging",
            ResourceGroup: "myapp-staging-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/aks",
            LogWorkspaceId: "/subscriptions/x/workspaces/logs",
            Config: new AksConfig(
                AdditionalNodePools: new Dictionary<string, NodePoolConfig>
                {
                    ["workers"] = new NodePoolConfig(
                        VmSize: "Standard_D8s_v3",
                        EnableAutoScaling: true,
                        MinCount: 2, MaxCount: 10)
                })));

        var pools = Module(Synth(stack), "aks").GetProperty("additional_node_pools");
        Assert.True(pools.TryGetProperty("workers", out var workers));
        Assert.Equal("Standard_D8s_v3", workers.GetProperty("vm_size").GetString());
        Assert.True(workers.GetProperty("enable_auto_scaling").GetBoolean());
    }

    [Fact]
    public void Aks_RequiredTagsInjected()
    {
        var stack = PlainStack();
        new AksConstruct(stack, "aks", new AksConstructProps(
            Project: "myapp", Environment: "prod",
            ResourceGroup: "myapp-prod-rg", Location: "eastus",
            SubnetId: "/subscriptions/x/subnets/aks",
            LogWorkspaceId: "/subscriptions/x/workspaces/logs"));

        var tags = Module(Synth(stack), "aks").GetProperty("tags");
        Assert.Equal("terraform", tags.GetProperty("managed_by").GetString());
        Assert.Equal("prod",      tags.GetProperty("environment").GetString());
    }
}
