import * as pulumi from "@pulumi/pulumi";
import * as tfm from "@pulumi/terraform-module";
import { requiredTags } from "./policy/tagging";

const VALID_ENVIRONMENTS = new Set(["dev", "staging", "prod"]);

const MODULE_REPO    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
const MODULE_VERSION = "v1.0.0";
const AKS_SOURCE     = `${MODULE_REPO}//modules/compute/aks?ref=${MODULE_VERSION}`;

export interface NodePoolConfig {
  readonly vmSize?:            string;
  readonly nodeCount?:         number;
  readonly enableAutoScaling?: boolean;
  readonly minCount?:          number;
  readonly maxCount?:          number;
  readonly labels?:            Record<string, string>;
  readonly taints?:            string[];
}

export interface AksConfig {
  readonly kubernetesVersion?:   string;
  readonly systemNodeVmSize?:    string;
  readonly systemNodeCount?:     number;
  readonly additionalNodePools?: Record<string, NodePoolConfig>;
  readonly adminGroupObjectIds?: string[];
  readonly serviceCidr?:         string;
  readonly dnsServiceIp?:        string;
  readonly extraTags?:           Record<string, string>;
}

export interface AksComponentArgs {
  readonly project:        string;
  readonly environment:    string;
  readonly resourceGroup:  string;
  readonly location:       string;
  readonly subnetId:       string;
  readonly logWorkspaceId: string;
  readonly config?:        AksConfig;
}

function serialiseNodePools(pools: Record<string, NodePoolConfig>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [poolName, pool] of Object.entries(pools)) {
    result[poolName] = {
      vm_size:             pool.vmSize ?? "Standard_D4s_v3",
      node_count:          pool.nodeCount ?? 2,
      enable_auto_scaling: pool.enableAutoScaling ?? false,
      min_count:           pool.minCount ?? 1,
      max_count:           pool.maxCount ?? 10,
      labels:              pool.labels ?? {},
      taints:              pool.taints ?? [],
    };
  }
  return result;
}

/**
 * AksComponent provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
 *
 * Delegates to the platform `modules/compute/aks` Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
export class AksComponent extends pulumi.ComponentResource {
  /** Resource ID of the managed cluster. */
  public readonly clusterId: pulumi.Output<string>;
  /** Name of the managed cluster. */
  public readonly clusterName: pulumi.Output<string>;
  /** Object ID of the kubelet managed identity. */
  public readonly kubeletIdentityObjectId: pulumi.Output<string>;
  /** Principal ID of the cluster system-assigned identity. */
  public readonly clusterIdentityPrincipalId: pulumi.Output<string>;

  constructor(name: string, args: AksComponentArgs, opts?: pulumi.ComponentResourceOptions) {
    if (!VALID_ENVIRONMENTS.has(args.environment)) {
      throw new Error(
        `environment must be one of [${[...VALID_ENVIRONMENTS].sort().join(", ")}], got "${args.environment}"`
      );
    }

    super("nautilus:containerservice:AksComponent", name, {}, opts);

    const cfg  = args.config ?? {};
    const tags = requiredTags(args.project, args.environment, cfg.extraTags);

    const mod = new tfm.Module(`${name}-aks`, {
      source: AKS_SOURCE,
      variables: {
        project:                    args.project,
        environment:                args.environment,
        resource_group_name:        args.resourceGroup,
        location:                   args.location,
        subnet_id:                  args.subnetId,
        log_analytics_workspace_id: args.logWorkspaceId,
        kubernetes_version:         cfg.kubernetesVersion ?? "1.29",
        system_node_vm_size:        cfg.systemNodeVmSize ?? "Standard_D2s_v3",
        system_node_count:          cfg.systemNodeCount ?? 3,
        additional_node_pools:      serialiseNodePools(cfg.additionalNodePools ?? {}),
        admin_group_object_ids:     cfg.adminGroupObjectIds ?? [],
        service_cidr:               cfg.serviceCidr ?? "10.240.0.0/16",
        dns_service_ip:             cfg.dnsServiceIp ?? "10.240.0.10",
        tags,
      },
    }, { parent: this });

    this.clusterId                  = mod.getOutput("cluster_id");
    this.clusterName                = mod.getOutput("cluster_name");
    this.kubeletIdentityObjectId    = mod.getOutput("kubelet_identity_object_id");
    this.clusterIdentityPrincipalId = mod.getOutput("cluster_identity_principal_id");

    this.registerOutputs({
      clusterId:                  this.clusterId,
      clusterName:                this.clusterName,
      kubeletIdentityObjectId:    this.kubeletIdentityObjectId,
      clusterIdentityPrincipalId: this.clusterIdentityPrincipalId,
    });
  }
}
