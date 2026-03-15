import { Construct } from "constructs";
import { TerraformModule } from "cdktf";
import { requiredTags } from "./policy/tagging";

const MODULE_SOURCE =
  "git::ssh://git@github.com/nautilus/terraform-modules.git" +
  "//modules/networking?ref=v1.4.0";

export interface SubnetDelegation {
  readonly name:    string;
  readonly service: string;
  readonly actions: string[];
}

export interface SubnetConfig {
  readonly addressPrefix:    string;
  readonly serviceEndpoints?: string[];
  readonly delegation?:       SubnetDelegation;
  readonly nsgRules?:         Record<string, unknown>[];
}

export interface NetworkConstructProps {
  readonly project:          string;
  readonly environment:      string;
  readonly resourceGroup:    string;
  readonly location:         string;
  readonly addressSpace:     string[];
  readonly subnets?:         Record<string, SubnetConfig>;
  readonly privateDnsZones?: string[];
  readonly extraTags?:       Record<string, string>;
}

export class NetworkConstruct extends Construct {
  private readonly _module: TerraformModule;

  constructor(scope: Construct, id: string, props: NetworkConstructProps) {
    super(scope, id);

    const subnets: Record<string, unknown> = {};
    for (const [name, cfg] of Object.entries(props.subnets ?? {})) {
      const s: Record<string, unknown> = {
        address_prefix:    cfg.addressPrefix,
        service_endpoints: cfg.serviceEndpoints ?? [],
      };
      if (cfg.delegation) {
        s["delegation"] = {
          name:    cfg.delegation.name,
          service: cfg.delegation.service,
          actions: cfg.delegation.actions,
        };
      }
      if (cfg.nsgRules) s["nsg_rules"] = cfg.nsgRules;
      subnets[name] = s;
    }

    this._module = new TerraformModule(this, "networking", {
      source: MODULE_SOURCE,
      variables: {
        project:             props.project,
        environment:         props.environment,
        resource_group_name: props.resourceGroup,
        location:            props.location,
        address_space:       props.addressSpace,
        subnets,
        private_dns_zones:   props.privateDnsZones ?? [],
        tags: requiredTags(props.project, props.environment, props.extraTags),
      },
    });
  }

  get vnetId(): string   { return this._module.getString("vnet_id"); }
  get vnetName(): string { return this._module.getString("vnet_name"); }

  /** Map of subnet name → subnet resource ID. */
  get subnetIds(): Record<string, string> {
    return this._module.get("subnet_ids") as Record<string, string>;
  }

  /** Map of DNS zone name → resource ID. */
  get dnsZoneIds(): Record<string, string> {
    return this._module.get("dns_zone_ids") as Record<string, string>;
  }
}
