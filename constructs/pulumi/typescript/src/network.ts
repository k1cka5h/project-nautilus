import * as pulumi from "@pulumi/pulumi";
import * as tfm from "@pulumi/terraform-module";
import { requiredTags } from "./policy/tagging";

const VALID_ENVIRONMENTS = new Set(["dev", "staging", "prod"]);

const MODULE_REPO    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
const MODULE_VERSION = "v1.0.0";
const NETWORK_SOURCE = `${MODULE_REPO}//modules/networking?ref=${MODULE_VERSION}`;

export interface SubnetDelegation {
  readonly name:    string;
  readonly service: string;
  readonly actions: string[];
}

export interface SubnetConfig {
  readonly addressPrefix:     string;
  readonly serviceEndpoints?: string[];
  readonly delegation?:       SubnetDelegation;
  readonly nsgRules?:         Record<string, unknown>[];
}

export interface NetworkComponentArgs {
  readonly project:          string;
  readonly environment:      string;
  readonly resourceGroup:    string;
  readonly location:         string;
  readonly addressSpace:     string[];
  readonly subnets?:         Record<string, SubnetConfig>;
  readonly privateDnsZones?: string[];
  readonly extraTags?:       Record<string, string>;
}

function serialiseSubnets(subnets: Record<string, SubnetConfig>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [name, cfg] of Object.entries(subnets)) {
    const entry: Record<string, unknown> = { address_prefix: cfg.addressPrefix };
    if (cfg.serviceEndpoints?.length) entry["service_endpoints"] = cfg.serviceEndpoints;
    if (cfg.delegation) {
      entry["delegation"] = {
        name:    cfg.delegation.name,
        service: cfg.delegation.service,
        actions: cfg.delegation.actions,
      };
    }
    if (cfg.nsgRules?.length) entry["nsg_rules"] = cfg.nsgRules;
    result[name] = entry;
  }
  return result;
}

/**
 * NetworkComponent provisions a VNet with subnets, NSGs, and private DNS zones.
 *
 * Delegates to the platform `modules/networking` Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
export class NetworkComponent extends pulumi.ComponentResource {
  /** Resource ID of the VNet. */
  public readonly vnetId: pulumi.Output<string>;
  /** Name of the VNet. */
  public readonly vnetName: pulumi.Output<string>;
  /** Map of subnet name → resource ID. */
  public readonly subnetIds: pulumi.Output<Record<string, string>>;
  /** Map of DNS zone name → resource ID. */
  public readonly dnsZoneIds: pulumi.Output<Record<string, string>>;

  constructor(name: string, args: NetworkComponentArgs, opts?: pulumi.ComponentResourceOptions) {
    if (!VALID_ENVIRONMENTS.has(args.environment)) {
      throw new Error(
        `environment must be one of [${[...VALID_ENVIRONMENTS].sort().join(", ")}], got "${args.environment}"`
      );
    }

    super("nautilus:network:NetworkComponent", name, {}, opts);

    const tags = requiredTags(args.project, args.environment, args.extraTags);

    const mod = new tfm.Module(`${name}-networking`, {
      source: NETWORK_SOURCE,
      variables: {
        project:             args.project,
        environment:         args.environment,
        resource_group_name: args.resourceGroup,
        location:            args.location,
        address_space:       args.addressSpace,
        subnets:             serialiseSubnets(args.subnets ?? {}),
        private_dns_zones:   args.privateDnsZones ?? [],
        tags,
      },
    }, { parent: this });

    this.vnetId     = mod.getOutput("vnet_id");
    this.vnetName   = mod.getOutput("vnet_name");
    this.subnetIds  = mod.getOutput("subnet_ids");
    this.dnsZoneIds = mod.getOutput("dns_zone_ids");

    this.registerOutputs({
      vnetId:     this.vnetId,
      vnetName:   this.vnetName,
      subnetIds:  this.subnetIds,
      dnsZoneIds: this.dnsZoneIds,
    });
  }
}
