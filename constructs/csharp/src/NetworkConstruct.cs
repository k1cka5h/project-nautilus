using Constructs;
using HashiCorp.Cdktf;
using Nautilus.Infra.Policy;

namespace Nautilus.Infra;

public record SubnetDelegation(string Name, string Service, string[] Actions);

public record SubnetConfig(
    string AddressPrefix,
    string[]? ServiceEndpoints = null,
    SubnetDelegation? Delegation = null,
    object[]? NsgRules = null);

public record NetworkConstructProps(
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
/// Wraps modules/networking from the platform Terraform module repo.
/// </summary>
public class NetworkConstruct : Construct
{
    private readonly TerraformModule _module;

    public NetworkConstruct(Construct scope, string id, NetworkConstructProps props)
        : base(scope, id)
    {
        var subnets = new Dictionary<string, object>();
        foreach (var (name, cfg) in props.Subnets ?? [])
        {
            var s = new Dictionary<string, object>
            {
                ["address_prefix"]    = cfg.AddressPrefix,
                ["service_endpoints"] = cfg.ServiceEndpoints ?? [],
            };
            if (cfg.Delegation is { } d)
                s["delegation"] = new Dictionary<string, object>
                {
                    ["name"]    = d.Name,
                    ["service"] = d.Service,
                    ["actions"] = d.Actions,
                };
            if (cfg.NsgRules is { } rules) s["nsg_rules"] = rules;
            subnets[name] = s;
        }

        _module = new TerraformModule(this, "networking", new TerraformModuleConfig
        {
            Source = "git::ssh://git@github.com/nautilus/terraform-modules.git" +
                     "//modules/networking?ref=v1.4.0",
            Variables = new Dictionary<string, object>
            {
                ["project"]             = props.Project,
                ["environment"]         = props.Environment,
                ["resource_group_name"] = props.ResourceGroup,
                ["location"]            = props.Location,
                ["address_space"]       = props.AddressSpace,
                ["subnets"]             = subnets,
                ["private_dns_zones"]   = props.PrivateDnsZones ?? [],
                ["tags"]                = Tagging.RequiredTags(props.Project, props.Environment, props.ExtraTags),
            },
        });
    }

    public string VnetId   => _module.GetString("vnet_id");
    public string VnetName => _module.GetString("vnet_name");

    /// <summary>Map of subnet name → subnet resource ID.</summary>
    public Dictionary<string, string> SubnetIds
        => (_module.Get("subnet_ids") as Dictionary<string, string>)!;

    /// <summary>Map of DNS zone name → resource ID.</summary>
    public Dictionary<string, string> DnsZoneIds
        => (_module.Get("dns_zone_ids") as Dictionary<string, string>)!;
}
