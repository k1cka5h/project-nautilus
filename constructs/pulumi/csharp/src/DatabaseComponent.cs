using System.Collections.Generic;
using System.Linq;
using Pulumi;
using Pulumi.TerraformModule;
using Nautilus.Infra.Pulumi.Policy;

namespace Nautilus.Infra.Pulumi;

public record PostgresConfig(
    string[] Databases,
    string Sku = "GP_Standard_D2s_v3",
    int StorageMb = 32768,
    string PgVersion = "15",
    bool HaEnabled = false,
    bool GeoRedundant = false,
    Dictionary<string, string>? ServerConfigs = null,
    Dictionary<string, string>? ExtraTags = null);

public record DatabaseComponentArgs(
    string Project,
    string Environment,
    string ResourceGroup,
    string Location,
    string SubnetId,
    string DnsZoneId,
    string AdminPassword,
    PostgresConfig? Config = null);

/// <summary>
/// Provisions a PostgreSQL Flexible Server with private VNet access.
///
/// Delegates to the platform <c>modules/database/postgres</c> Terraform module via
/// Pulumi-Terraform interop. Terraform creates every Azure resource;
/// Pulumi reads the outputs.
/// </summary>
public class DatabaseComponent : ComponentResource
{
    private const string ModuleRepo     = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private const string ModuleVersion  = "v1.0.0";
    private const string PostgresSource = $"{ModuleRepo}//modules/database/postgres?ref={ModuleVersion}";

    private static readonly HashSet<string> ValidEnvironments = ["dev", "staging", "prod"];

    /// <summary>Fully-qualified domain name for client connections.</summary>
    public Output<string> Fqdn { get; }
    /// <summary>Resource ID of the flexible server.</summary>
    public Output<string> ServerId { get; }
    /// <summary>Name of the flexible server.</summary>
    public Output<string> ServerName { get; }

    public DatabaseComponent(string name, DatabaseComponentArgs args, ComponentResourceOptions? opts = null)
        : base("nautilus:database:DatabaseComponent", name, opts)
    {
        if (!ValidEnvironments.Contains(args.Environment))
            throw new System.ArgumentException(
                $"environment must be one of [{string.Join(", ", ValidEnvironments.OrderBy(e => e))}], got \"{args.Environment}\"");

        var cfg  = args.Config ?? new PostgresConfig(Databases: []);
        var tags = Tagging.RequiredTags(args.Project, args.Environment, cfg.ExtraTags);

        var mod = new Module($"{name}-postgres", new ModuleArgs
        {
            Source = PostgresSource,
            Variables =
            {
                ["project"]                 = args.Project,
                ["environment"]             = args.Environment,
                ["resource_group_name"]     = args.ResourceGroup,
                ["location"]                = args.Location,
                ["delegated_subnet_id"]     = args.SubnetId,
                ["private_dns_zone_id"]     = args.DnsZoneId,
                ["administrator_password"]  = args.AdminPassword,
                ["databases"]               = cfg.Databases,
                ["sku_name"]                = cfg.Sku,
                ["storage_mb"]              = cfg.StorageMb,
                ["pg_version"]              = cfg.PgVersion,
                ["high_availability_mode"]  = cfg.HaEnabled ? "ZoneRedundant" : "Disabled",
                ["geo_redundant_backup"]    = cfg.GeoRedundant,
                ["server_configurations"]   = cfg.ServerConfigs ?? new(),
                ["tags"]                    = tags,
            },
        }, new CustomResourceOptions { Parent = this });

        Fqdn       = mod.GetOutput("fqdn");
        ServerId   = mod.GetOutput("server_id");
        ServerName = mod.GetOutput("server_name");

        RegisterOutputs(new Dictionary<string, object?>
        {
            ["fqdn"]       = Fqdn,
            ["serverId"]   = ServerId,
            ["serverName"] = ServerName,
        });
    }
}
