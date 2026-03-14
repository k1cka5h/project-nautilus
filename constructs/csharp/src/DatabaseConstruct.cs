using Constructs;
using HashiCorp.Cdktf;
using MyOrg.Infra.Policy;

namespace MyOrg.Infra;

public record PostgresConfig(
    string[] Databases,
    string Sku = "GP_Standard_D2s_v3",
    int StorageMb = 32768,
    string PgVersion = "15",
    bool HaEnabled = false,
    bool GeoRedundant = false,
    Dictionary<string, string>? ServerConfigs = null,
    Dictionary<string, string>? ExtraTags = null);

public record DatabaseConstructProps(
    string Project,
    string Environment,
    string ResourceGroup,
    string Location,
    string SubnetId,
    string DnsZoneId,
    string AdminPassword,
    PostgresConfig? Config = null);

/// <summary>
/// Provisions an Azure PostgreSQL Flexible Server with private VNet access.
/// Wraps modules/database/postgres from the platform Terraform module repo.
/// </summary>
public class DatabaseConstruct : Construct
{
    private readonly TerraformModule _module;

    public DatabaseConstruct(Construct scope, string id, DatabaseConstructProps props)
        : base(scope, id)
    {
        var cfg = props.Config ?? new PostgresConfig([]);

        _module = new TerraformModule(this, "postgres", new TerraformModuleConfig
        {
            Source = "git::ssh://git@github.com/myorg/terraform-modules.git" +
                     "//modules/database/postgres?ref=v1.4.0",
            Variables = new Dictionary<string, object>
            {
                ["project"]                = props.Project,
                ["environment"]            = props.Environment,
                ["resource_group_name"]    = props.ResourceGroup,
                ["location"]               = props.Location,
                ["delegated_subnet_id"]    = props.SubnetId,
                ["private_dns_zone_id"]    = props.DnsZoneId,
                ["administrator_password"] = props.AdminPassword,
                ["databases"]              = cfg.Databases,
                ["sku_name"]               = cfg.Sku,
                ["storage_mb"]             = cfg.StorageMb,
                ["pg_version"]             = cfg.PgVersion,
                ["high_availability_mode"] = cfg.HaEnabled ? "ZoneRedundant" : "Disabled",
                ["geo_redundant_backup"]   = cfg.GeoRedundant,
                ["server_configurations"]  = cfg.ServerConfigs ?? new Dictionary<string, string>(),
                ["tags"] = Tagging.RequiredTags(props.Project, props.Environment, cfg.ExtraTags),
            },
        });
    }

    /// <summary>FQDN for connecting to the server. Use as the connection host.</summary>
    public string Fqdn       => _module.GetString("fqdn");
    public string ServerId   => _module.GetString("server_id");
    public string ServerName => _module.GetString("server_name");
}
