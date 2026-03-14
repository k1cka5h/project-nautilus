import { Construct } from "constructs";
import { TerraformModule } from "cdktf";
import { requiredTags } from "./policy/tagging";

const MODULE_SOURCE =
  "git::ssh://git@github.com/myorg/terraform-modules.git" +
  "//modules/database/postgres?ref=v1.4.0";

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

export interface DatabaseConstructProps {
  readonly project:       string;
  readonly environment:   string;
  readonly resourceGroup: string;
  readonly location:      string;
  readonly subnetId:      string;
  readonly dnsZoneId:     string;
  readonly adminPassword: string;
  readonly config?:       PostgresConfig;
}

export class DatabaseConstruct extends Construct {
  private readonly _module: TerraformModule;

  constructor(scope: Construct, id: string, props: DatabaseConstructProps) {
    super(scope, id);

    const cfg = props.config ?? {};

    this._module = new TerraformModule(this, "postgres", {
      source: MODULE_SOURCE,
      variables: {
        project:                props.project,
        environment:            props.environment,
        resource_group_name:    props.resourceGroup,
        location:               props.location,
        delegated_subnet_id:    props.subnetId,
        private_dns_zone_id:    props.dnsZoneId,
        administrator_password: props.adminPassword,
        databases:              cfg.databases             ?? [],
        sku_name:               cfg.sku                  ?? "GP_Standard_D2s_v3",
        storage_mb:             cfg.storageMb            ?? 32768,
        pg_version:             cfg.pgVersion            ?? "15",
        high_availability_mode: cfg.haEnabled            ? "ZoneRedundant" : "Disabled",
        geo_redundant_backup:   cfg.geoRedundant         ?? false,
        server_configurations:  cfg.serverConfigs        ?? {},
        tags: requiredTags(props.project, props.environment, cfg.extraTags),
      },
    });
  }

  /** FQDN for connecting to the server. Use as the connection host. */
  get fqdn(): string       { return this._module.getString("fqdn"); }
  get serverId(): string   { return this._module.getString("server_id"); }
  get serverName(): string { return this._module.getString("server_name"); }
}
