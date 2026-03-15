package com.nautilus.infra.pulumi;

import com.nautilus.infra.pulumi.policy.Tagging;
import com.pulumi.core.Output;
import com.pulumi.resources.ComponentResource;
import com.pulumi.resources.ComponentResourceOptions;
import com.pulumi.resources.CustomResourceOptions;
import com.pulumi.terraformmodule.Module;
import com.pulumi.terraformmodule.ModuleArgs;

import java.util.*;

/**
 * Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
 *
 * <p>Delegates to the platform {@code modules/compute/aks} Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
public class AksComponent extends ComponentResource {

    private static final String MODULE_REPO    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private static final String MODULE_VERSION = "v1.0.0";
    private static final String AKS_SOURCE     = MODULE_REPO + "//modules/compute/aks?ref=" + MODULE_VERSION;
    private static final Set<String> VALID_ENVIRONMENTS = Set.of("dev", "staging", "prod");

    // ── Config types ────────────────────────────────────────────────────────

    public static final class NodePoolConfig {
        public final String vmSize;
        public final int nodeCount;
        public final boolean enableAutoScaling;
        public final int minCount, maxCount;
        public final Map<String, String> labels;
        public final List<String> taints;

        private NodePoolConfig(Builder b) {
            this.vmSize = b.vmSize; this.nodeCount = b.nodeCount;
            this.enableAutoScaling = b.enableAutoScaling;
            this.minCount = b.minCount; this.maxCount = b.maxCount;
            this.labels = b.labels; this.taints = b.taints;
        }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String vmSize = "Standard_D4s_v3";
            private int nodeCount = 2;
            private boolean enableAutoScaling = false;
            private int minCount = 1, maxCount = 10;
            private Map<String, String> labels = Map.of();
            private List<String> taints = List.of();

            public Builder vmSize(String v)              { this.vmSize = v;             return this; }
            public Builder nodeCount(int v)              { this.nodeCount = v;           return this; }
            public Builder enableAutoScaling(boolean v)  { this.enableAutoScaling = v;  return this; }
            public Builder minCount(int v)               { this.minCount = v;           return this; }
            public Builder maxCount(int v)               { this.maxCount = v;           return this; }
            public Builder labels(Map<String, String> v) { this.labels = v;             return this; }
            public Builder taints(List<String> v)        { this.taints = v;             return this; }
            public NodePoolConfig build()                 { return new NodePoolConfig(this); }
        }
    }

    public static final class AksConfig {
        public final String kubernetesVersion, systemNodeVmSize;
        public final int systemNodeCount;
        public final Map<String, NodePoolConfig> additionalNodePools;
        public final List<String> adminGroupObjectIds;
        public final String serviceCidr, dnsServiceIp;
        public final Map<String, String> extraTags;

        private AksConfig(Builder b) {
            this.kubernetesVersion   = b.kubernetesVersion;
            this.systemNodeVmSize    = b.systemNodeVmSize;
            this.systemNodeCount     = b.systemNodeCount;
            this.additionalNodePools = b.additionalNodePools;
            this.adminGroupObjectIds = b.adminGroupObjectIds;
            this.serviceCidr         = b.serviceCidr;
            this.dnsServiceIp        = b.dnsServiceIp;
            this.extraTags           = b.extraTags;
        }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String kubernetesVersion = "1.29";
            private String systemNodeVmSize  = "Standard_D2s_v3";
            private int systemNodeCount      = 3;
            private Map<String, NodePoolConfig> additionalNodePools = Map.of();
            private List<String> adminGroupObjectIds = List.of();
            private String serviceCidr  = "10.240.0.0/16";
            private String dnsServiceIp = "10.240.0.10";
            private Map<String, String> extraTags = Map.of();

            public Builder kubernetesVersion(String v)                    { this.kubernetesVersion = v;   return this; }
            public Builder systemNodeVmSize(String v)                     { this.systemNodeVmSize = v;    return this; }
            public Builder systemNodeCount(int v)                         { this.systemNodeCount = v;     return this; }
            public Builder additionalNodePools(Map<String, NodePoolConfig> v) { this.additionalNodePools = v; return this; }
            public Builder adminGroupObjectIds(List<String> v)            { this.adminGroupObjectIds = v; return this; }
            public Builder serviceCidr(String v)                          { this.serviceCidr = v;         return this; }
            public Builder dnsServiceIp(String v)                         { this.dnsServiceIp = v;        return this; }
            public Builder extraTags(Map<String, String> v)               { this.extraTags = v;           return this; }
            public AksConfig build()                                       { return new AksConfig(this); }
        }
    }

    public static final class AksComponentArgs {
        public final String project, environment, resourceGroup, location, subnetId, logWorkspaceId;
        public final AksConfig config;

        private AksComponentArgs(Builder b) {
            this.project = b.project; this.environment = b.environment;
            this.resourceGroup = b.resourceGroup; this.location = b.location;
            this.subnetId = b.subnetId; this.logWorkspaceId = b.logWorkspaceId;
            this.config = b.config;
        }

        public static Builder builder(String project, String environment, String resourceGroup,
                                      String location, String subnetId, String logWorkspaceId) {
            return new Builder(project, environment, resourceGroup, location, subnetId, logWorkspaceId);
        }

        public static final class Builder {
            private final String project, environment, resourceGroup, location, subnetId, logWorkspaceId;
            private AksConfig config = AksConfig.builder().build();

            private Builder(String p, String e, String rg, String l, String s, String lw) {
                this.project = p; this.environment = e; this.resourceGroup = rg;
                this.location = l; this.subnetId = s; this.logWorkspaceId = lw;
            }
            public Builder config(AksConfig v) { this.config = v; return this; }
            public AksComponentArgs build()     { return new AksComponentArgs(this); }
        }
    }

    // ── Outputs ─────────────────────────────────────────────────────────────

    /** Resource ID of the managed cluster. */
    public final Output<String> clusterId;
    /** Name of the managed cluster. */
    public final Output<String> clusterName;
    /** Object ID of the kubelet managed identity. */
    public final Output<String> kubeletIdentityObjectId;
    /** Principal ID of the cluster system-assigned identity. */
    public final Output<String> clusterIdentityPrincipalId;

    // ── Constructor ──────────────────────────────────────────────────────────

    public AksComponent(String name, AksComponentArgs args) {
        this(name, args, null);
    }

    public AksComponent(String name, AksComponentArgs args, ComponentResourceOptions opts) {
        super("nautilus:containerservice:AksComponent", name, opts);

        if (!VALID_ENVIRONMENTS.contains(args.environment))
            throw new IllegalArgumentException(
                "environment must be one of " + new TreeSet<>(VALID_ENVIRONMENTS) + ", got \"" + args.environment + "\"");

        var cfg  = args.config;
        var tags = Tagging.requiredTags(args.project, args.environment, cfg.extraTags);

        var nodePools = new LinkedHashMap<String, Object>();
        for (var entry : cfg.additionalNodePools.entrySet()) {
            var p = entry.getValue();
            nodePools.put(entry.getKey(), Map.of(
                "vm_size", p.vmSize, "node_count", p.nodeCount,
                "enable_auto_scaling", p.enableAutoScaling,
                "min_count", p.minCount, "max_count", p.maxCount,
                "labels", p.labels, "taints", p.taints
            ));
        }

        var mod = new Module(name + "-aks", ModuleArgs.builder()
            .source(AKS_SOURCE)
            .variables(Map.of(
                "project",                    args.project,
                "environment",                args.environment,
                "resource_group_name",        args.resourceGroup,
                "location",                   args.location,
                "subnet_id",                  args.subnetId,
                "log_analytics_workspace_id", args.logWorkspaceId,
                "kubernetes_version",         cfg.kubernetesVersion,
                "system_node_vm_size",        cfg.systemNodeVmSize,
                "system_node_count",          cfg.systemNodeCount,
                "additional_node_pools",      nodePools,
                "admin_group_object_ids",     cfg.adminGroupObjectIds,
                "service_cidr",               cfg.serviceCidr,
                "dns_service_ip",             cfg.dnsServiceIp,
                "tags",                       tags
            ))
            .build(),
            CustomResourceOptions.builder().parent(this).build()
        );

        this.clusterId                  = mod.getOutput("cluster_id");
        this.clusterName                = mod.getOutput("cluster_name");
        this.kubeletIdentityObjectId    = mod.getOutput("kubelet_identity_object_id");
        this.clusterIdentityPrincipalId = mod.getOutput("cluster_identity_principal_id");

        this.registerOutputs(Map.of(
            "clusterId",                  clusterId,
            "clusterName",                clusterName,
            "kubeletIdentityObjectId",    kubeletIdentityObjectId,
            "clusterIdentityPrincipalId", clusterIdentityPrincipalId
        ));
    }
}
