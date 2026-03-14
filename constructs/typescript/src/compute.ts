import { Construct } from "constructs";
import { TerraformModule } from "cdktf";
import { requiredTags } from "./policy/tagging";

const MODULE_SOURCE =
  "git::ssh://git@github.com/nautilus/terraform-modules.git" +
  "//modules/compute/aks?ref=v1.4.0";

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
  readonly kubernetesVersion?:     string;
  readonly systemNodeVmSize?:      string;
  readonly systemNodeCount?:       number;
  readonly additionalNodePools?:   Record<string, NodePoolConfig>;
  readonly adminGroupObjectIds?:   string[];
  readonly serviceCidr?:           string;
  readonly dnsServiceIp?:          string;
  readonly extraTags?:             Record<string, string>;
}

export interface AksConstructProps {
  readonly project:        string;
  readonly environment:    string;
  readonly resourceGroup:  string;
  readonly location:       string;
  readonly subnetId:       string;
  readonly logWorkspaceId: string;
  readonly config?:        AksConfig;
}

export class AksConstruct extends Construct {
  private readonly _module: TerraformModule;

  constructor(scope: Construct, id: string, props: AksConstructProps) {
    super(scope, id);

    const cfg = props.config ?? {};

    const additionalNodePools: Record<string, unknown> = {};
    for (const [name, pool] of Object.entries(cfg.additionalNodePools ?? {})) {
      additionalNodePools[name] = {
        vm_size:             pool.vmSize            ?? "Standard_D4s_v3",
        node_count:          pool.nodeCount         ?? 2,
        enable_auto_scaling: pool.enableAutoScaling ?? false,
        min_count:           pool.minCount          ?? 1,
        max_count:           pool.maxCount          ?? 10,
        labels:              pool.labels            ?? {},
        taints:              pool.taints            ?? [],
      };
    }

    this._module = new TerraformModule(this, "aks", {
      source: MODULE_SOURCE,
      variables: {
        project:                    props.project,
        environment:                props.environment,
        resource_group_name:        props.resourceGroup,
        location:                   props.location,
        subnet_id:                  props.subnetId,
        log_analytics_workspace_id: props.logWorkspaceId,
        kubernetes_version:         cfg.kubernetesVersion   ?? "1.29",
        system_node_vm_size:        cfg.systemNodeVmSize    ?? "Standard_D2s_v3",
        system_node_count:          cfg.systemNodeCount     ?? 3,
        additional_node_pools:      additionalNodePools,
        admin_group_object_ids:     cfg.adminGroupObjectIds ?? [],
        service_cidr:               cfg.serviceCidr         ?? "10.240.0.0/16",
        dns_service_ip:             cfg.dnsServiceIp        ?? "10.240.0.10",
        tags: requiredTags(props.project, props.environment, cfg.extraTags),
      },
    });
  }

  get clusterId(): string                    { return this._module.getString("cluster_id"); }
  get clusterName(): string                  { return this._module.getString("cluster_name"); }
  /** Assign ACR pull and Key Vault read to this identity. */
  get kubeletIdentityObjectId(): string      { return this._module.getString("kubelet_identity_object_id"); }
  /** Assign Network Contributor to this identity. */
  get clusterIdentityPrincipalId(): string   { return this._module.getString("cluster_identity_principal_id"); }
}
