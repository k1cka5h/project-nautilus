using System.Collections.Generic;
using System.Linq;
using Pulumi;
using Pulumi.TerraformModule;
using Nautilus.Infra.Pulumi.Policy;

namespace Nautilus.Infra.Pulumi;

public record SubnetDelegation(string Name, string Service, string[] Actions);

public record SubnetConfig(
    string AddressPrefix,
    string[]? ServiceEndpoints = null,
    SubnetDelegation? Delegation = null,
    object[]? NsgRules = null);

public record NetworkComponentArgs(
    string Project,
    string Environment,
    string ResourceGroup,
    string Location,
    string[] AddressSpace,
    Dictionary<string, SubnetConfig>? Subnets = null,
    string[]? PrivateDnsZones = null,
    Dictionary<string, string>? ExtraTags = null);

/// <summary>
/// Provisions a VNet with subnets, NSGs, and private DNS zones.
///
/// Delegates to the platform <c>modules/networking</c> Terraform module via
/// Pulumi-Terraform interop. Terraform creates every Azure resource;
/// Pulumi reads the outputs.
/// </summary>
public class NetworkComponent : ComponentResource
{
    private const string ModuleRepo    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private const string ModuleVersion = "v1.0.0";
    private const string NetworkSource = $"{ModuleRepo}//modules/networking?ref={ModuleVersion}";

    private static readonly HashSet<string> ValidEnvironments = ["dev", "staging", "prod"];

    /// <summary>Resource ID of the VNet.</summary>
    public Output<string> VnetId { get; }
    /// <summary>Name of the VNet.</summary>
    public Output<string> VnetName { get; }
    /// <summary>Map of subnet name → resource ID.</summary>
    public Output<ImmutableDictionary<string, string>> SubnetIds { get; }
    /// <summary>Map of DNS zone name → resource ID.</summary>
    public Output<ImmutableDictionary<string, string>> DnsZoneIds { get; }

    public NetworkComponent(string name, NetworkComponentArgs args, ComponentResourceOptions? opts = null)
        : base("nautilus:network:NetworkComponent", name, opts)
    {
        if (!ValidEnvironments.Contains(args.Environment))
            throw new System.ArgumentException(
                $"environment must be one of [{string.Join(", ", ValidEnvironments.OrderBy(e => e))}], got \"{args.Environment}\"");

        var tags = Tagging.RequiredTags(args.Project, args.Environment, args.ExtraTags);

        var subnets = new Dictionary<string, object>();
        foreach (var (subnetName, cfg) in args.Subnets ?? new())
        {
            var entry = new Dictionary<string, object> { ["address_prefix"] = cfg.AddressPrefix };
            if (cfg.ServiceEndpoints?.Length > 0) entry["service_endpoints"] = cfg.ServiceEndpoints;
            if (cfg.Delegation is not null)
                entry["delegation"] = new Dictionary<string, object>
                {
                    ["name"]    = cfg.Delegation.Name,
                    ["service"] = cfg.Delegation.Service,
                    ["actions"] = cfg.Delegation.Actions,
                };
            if (cfg.NsgRules?.Length > 0) entry["nsg_rules"] = cfg.NsgRules;
            subnets[subnetName] = entry;
        }

        var mod = new Module($"{name}-networking", new ModuleArgs
        {
            Source = NetworkSource,
            Variables =
            {
                ["project"]             = args.Project,
                ["environment"]         = args.Environment,
                ["resource_group_name"] = args.ResourceGroup,
                ["location"]            = args.Location,
                ["address_space"]       = args.AddressSpace,
                ["subnets"]             = subnets,
                ["private_dns_zones"]   = args.PrivateDnsZones ?? [],
                ["tags"]                = tags,
            },
        }, new CustomResourceOptions { Parent = this });

        VnetId     = mod.GetOutput("vnet_id");
        VnetName   = mod.GetOutput("vnet_name");
        SubnetIds  = mod.GetOutput("subnet_ids");
        DnsZoneIds = mod.GetOutput("dns_zone_ids");

        RegisterOutputs(new Dictionary<string, object?>
        {
            ["vnetId"]     = VnetId,
            ["vnetName"]   = VnetName,
            ["subnetIds"]  = SubnetIds,
            ["dnsZoneIds"] = DnsZoneIds,
        });
    }
}
