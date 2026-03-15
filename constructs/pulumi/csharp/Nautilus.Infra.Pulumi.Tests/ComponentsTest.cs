using System.Collections.Immutable;
using Pulumi.Testing;
using Xunit;
using Nautilus.Infra.Pulumi;
using Nautilus.Infra.Pulumi.Policy;

namespace Nautilus.Infra.Pulumi.Tests;

/// <summary>
/// Component unit tests — C#
/// ==========================
/// Uses Pulumi mock infrastructure to verify component wiring
/// without deploying any real Azure resources.
///
/// Run:
///   dotnet test Nautilus.Infra.Pulumi.Tests/
/// </summary>
public class ComponentsTest
{
    // ── Tagging ────────────────────────────────────────────────────────────────

    [Fact]
    public void RequiredTags_ContainsMandatoryKeys()
    {
        var tags = Tagging.RequiredTags("myapp", "dev");
        Assert.Equal("pulumi",  tags["managed_by"]);
        Assert.Equal("myapp",   tags["project"]);
        Assert.Equal("dev",     tags["environment"]);
    }

    [Fact]
    public void RequiredTags_OverridesExtraKey()
    {
        var extra = new Dictionary<string, string>
        {
            ["managed_by"] = "manual",
            ["team"]       = "platform",
        };
        var tags = Tagging.RequiredTags("myapp", "prod", extra);
        Assert.Equal("pulumi",   tags["managed_by"]);
        Assert.Equal("platform", tags["team"]);
    }


    // ── NetworkComponent ───────────────────────────────────────────────────────

    [Fact]
    public void Network_ThrowsOnInvalidEnvironment()
    {
        Assert.Throws<ArgumentException>(() =>
            new NetworkComponent("net", new NetworkComponentArgs(
                Project:       "myapp",
                Environment:   "uat",
                ResourceGroup: "rg",
                Location:      "eastus",
                AddressSpace:  ["10.0.0.0/16"])));
    }

    [Fact]
    public async Task Network_VnetIdIsOutput()
    {
        var resources = await Testing.RunAsync<NetworkComponentStack>();
        var vnet = resources.OfType<global::Pulumi.AzureNative.Network.VirtualNetwork>().FirstOrDefault();
        Assert.NotNull(vnet);
    }

    [Fact]
    public void Network_SubnetDelegationConstructed()
    {
        var deleg = new SubnetDelegation(
            Name:    "postgres",
            Service: "Microsoft.DBforPostgreSQL/flexibleServers",
            Actions: ["Microsoft.Network/virtualNetworks/subnets/join/action"]);
        Assert.Equal("Microsoft.DBforPostgreSQL/flexibleServers", deleg.Service);
    }


    // ── DatabaseComponent ──────────────────────────────────────────────────────

    [Fact]
    public void Database_ThrowsOnInvalidEnvironment()
    {
        Assert.Throws<ArgumentException>(() =>
            new DatabaseComponent("db", new DatabaseComponentArgs(
                Project:       "myapp",
                Environment:   "qa",
                ResourceGroup: "rg",
                Location:      "eastus",
                SubnetId:      "sn",
                DnsZoneId:     "dns",
                AdminPassword: "secret")));
    }

    [Fact]
    public void Database_HaEnabledConstructed()
    {
        // Verify the record is created correctly with HA enabled — resource-level
        // validation happens at deployment time.
        var cfg = new PostgresConfig(
            Databases: ["appdb"],
            HaEnabled: true);
        Assert.True(cfg.HaEnabled);
    }

    [Fact]
    public void Database_DefaultConfigHaDisabled()
    {
        var cfg = new PostgresConfig([]);
        Assert.False(cfg.HaEnabled);
        Assert.Equal(32, cfg.StorageGb);
        Assert.Equal("15", cfg.PgVersion);
    }


    // ── AksComponent ──────────────────────────────────────────────────────────

    [Fact]
    public void Aks_ThrowsOnInvalidEnvironment()
    {
        Assert.Throws<ArgumentException>(() =>
            new AksComponent("aks", new AksComponentArgs(
                Project:        "myapp",
                Environment:    "badenv",
                ResourceGroup:  "rg",
                Location:       "eastus",
                SubnetId:       "sn",
                LogWorkspaceId: "ws")));
    }

    [Fact]
    public void Aks_DefaultConfigValues()
    {
        var cfg = new AksConfig();
        Assert.Equal("1.29",              cfg.KubernetesVersion);
        Assert.Equal("Standard_D2s_v3",   cfg.SystemNodeVmSize);
        Assert.Equal(3,                   cfg.SystemNodeCount);
        Assert.Equal("10.240.0.0/16",     cfg.ServiceCidr);
        Assert.Equal("10.240.0.10",       cfg.DnsServiceIp);
    }

    [Fact]
    public void Aks_NodePoolConfigDefaults()
    {
        var pool = new NodePoolConfig();
        Assert.Equal("Standard_D4s_v3", pool.VmSize);
        Assert.Equal(2,  pool.NodeCount);
        Assert.False(pool.EnableAutoScaling);
        Assert.Equal(1,  pool.MinCount);
        Assert.Equal(10, pool.MaxCount);
    }
}

// ── Minimal stack for Testing.RunAsync ────────────────────────────────────────

public class NetworkComponentStack : global::Pulumi.Stack
{
    public NetworkComponentStack()
    {
        new NetworkComponent("net", new NetworkComponentArgs(
            Project:       "myapp",
            Environment:   "dev",
            ResourceGroup: "myapp-dev-rg",
            Location:      "eastus",
            AddressSpace:  ["10.10.0.0/16"],
            Subnets: new Dictionary<string, SubnetConfig>
            {
                ["aks"] = new SubnetConfig(AddressPrefix: "10.10.0.0/22"),
            }));
    }
}
