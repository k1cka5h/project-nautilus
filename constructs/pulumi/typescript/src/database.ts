import * as pulumi from "@pulumi/pulumi";
import * as tfm from "@pulumi/terraform-module";
import { requiredTags } from "./policy/tagging";

const VALID_ENVIRONMENTS = new Set(["dev", "staging", "prod"]);

const MODULE_REPO     = "git::ssh://git@github.com/nautilus/terraform-modules.git";
const MODULE_VERSION  = "v1.0.0";
const POSTGRES_SOURCE = `${MODULE_REPO}//modules/database/postgres?ref=${MODULE_VERSION}`;

export interface PostgresConfig {
  readonly databases?:     string[];
  readonly sku?:           string;
  readonly storageMb?:     number;
  readonly pgVersion?:     string;
  readonly haEnabled?:     boolean;
  readonly geoRedundant?:  boolean;
  readonly serverConfigs?: Record<string, string>;
  readonly extraTags?:     Record<string, string>;
}

export interface DatabaseComponentArgs {
  readonly project:        string;
  readonly environment:    string;
  readonly resourceGroup:  string;
  readonly location:       string;
  readonly subnetId:       string;
  readonly dnsZoneId:      string;
  readonly adminPassword:  string;
  readonly config?:        PostgresConfig;
}

/**
 * DatabaseComponent provisions a PostgreSQL Flexible Server with private VNet access.
 *
 * Delegates to the platform `modules/database/postgres` Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
export class DatabaseComponent extends pulumi.ComponentResource {
  /** Fully-qualified domain name for client connections. */
  public readonly fqdn: pulumi.Output<string>;
  /** Resource ID of the flexible server. */
  public readonly serverId: pulumi.Output<string>;
  /** Name of the flexible server. */
  public readonly serverName: pulumi.Output<string>;

  constructor(name: string, args: DatabaseComponentArgs, opts?: pulumi.ComponentResourceOptions) {
    if (!VALID_ENVIRONMENTS.has(args.environment)) {
      throw new Error(
        `environment must be one of [${[...VALID_ENVIRONMENTS].sort().join(", ")}], got "${args.environment}"`
      );
    }

    super("nautilus:database:DatabaseComponent", name, {}, opts);

    const cfg  = args.config ?? {};
    const tags = requiredTags(args.project, args.environment, cfg.extraTags);

    const mod = new tfm.Module(`${name}-postgres`, {
      source: POSTGRES_SOURCE,
      variables: {
        project:                args.project,
        environment:            args.environment,
        resource_group_name:    args.resourceGroup,
        location:               args.location,
        delegated_subnet_id:    args.subnetId,
        private_dns_zone_id:    args.dnsZoneId,
        administrator_password: args.adminPassword,
        databases:              cfg.databases ?? [],
        sku_name:               cfg.sku ?? "GP_Standard_D2s_v3",
        storage_mb:             cfg.storageMb ?? 32768,
        pg_version:             cfg.pgVersion ?? "15",
        high_availability_mode: cfg.haEnabled ? "ZoneRedundant" : "Disabled",
        geo_redundant_backup:   cfg.geoRedundant ?? false,
        server_configurations:  cfg.serverConfigs ?? {},
        tags,
      },
    }, { parent: this });

    this.fqdn       = mod.getOutput("fqdn");
    this.serverId   = mod.getOutput("server_id");
    this.serverName = mod.getOutput("server_name");

    this.registerOutputs({
      fqdn:       this.fqdn,
      serverId:   this.serverId,
      serverName: this.serverName,
    });
  }
}
