package com.k1cka5h.infra.constructs;

import software.constructs.Construct;
import com.hashicorp.cdktf.TerraformModule;
import com.k1cka5h.infra.policy.Tagging;

import java.util.*;

/**
 * Provisions an AKS cluster with Azure CNI, AAD RBAC, and Log Analytics.
 * Wraps modules/compute/aks from the platform Terraform module repo.
 */
public class AksConstruct extends Construct {

    private static final String MODULE_SOURCE =
        "git::ssh://git@github.com/k1cka5h/terraform-modules.git" +
        "//modules/compute/aks?ref=v1.4.0";

    private final TerraformModule module;

    public AksConstruct(Construct scope, String id, AksConstructProps props) {
        super(scope, id);

        var cfg = props.getConfig() != null ? props.getConfig() : AksConfig.builder().build();

        var pools = new HashMap<String, Object>();
        for (var entry : cfg.getAdditionalNodePools().entrySet()) {
            var p = entry.getValue();
            pools.put(entry.getKey(), Map.of(
                "vm_size",             p.getVmSize(),
                "node_count",          p.getNodeCount(),
                "enable_auto_scaling", p.isEnableAutoScaling(),
                "min_count",           p.getMinCount(),
                "max_count",           p.getMaxCount(),
                "labels",              p.getLabels(),
                "taints",              p.getTaints()
            ));
        }

        var variables = new HashMap<String, Object>();
        variables.put("project",                    props.getProject());
        variables.put("environment",                props.getEnvironment());
        variables.put("resource_group_name",        props.getResourceGroup());
        variables.put("location",                   props.getLocation());
        variables.put("subnet_id",                  props.getSubnetId());
        variables.put("log_analytics_workspace_id", props.getLogWorkspaceId());
        variables.put("kubernetes_version",         cfg.getKubernetesVersion());
        variables.put("system_node_vm_size",        cfg.getSystemNodeVmSize());
        variables.put("system_node_count",          cfg.getSystemNodeCount());
        variables.put("additional_node_pools",      pools);
        variables.put("admin_group_object_ids",     cfg.getAdminGroupObjectIds());
        variables.put("service_cidr",               cfg.getServiceCidr());
        variables.put("dns_service_ip",             cfg.getDnsServiceIp());
        variables.put("tags",                       Tagging.requiredTags(props.getProject(), props.getEnvironment(), cfg.getExtraTags()));

        this.module = TerraformModule.Builder.create(this, "aks")
                .source(MODULE_SOURCE)
                .variables(variables)
                .build();
    }

    public String getClusterId()                  { return module.getString("cluster_id"); }
    public String getClusterName()                { return module.getString("cluster_name"); }
    /** Assign ACR pull and Key Vault read to this identity. */
    public String getKubeletIdentityObjectId()    { return module.getString("kubelet_identity_object_id"); }
    /** Assign Network Contributor to this identity. */
    public String getClusterIdentityPrincipalId() { return module.getString("cluster_identity_principal_id"); }


    // ── NodePoolConfig ────────────────────────────────────────────────────────

    public static final class NodePoolConfig {
        private final String vmSize;
        private final int nodeCount, minCount, maxCount;
        private final boolean enableAutoScaling;
        private final Map<String, String> labels;
        private final List<String> taints;

        private NodePoolConfig(Builder b) {
            this.vmSize            = b.vmSize;
            this.nodeCount         = b.nodeCount;
            this.enableAutoScaling = b.enableAutoScaling;
            this.minCount          = b.minCount;
            this.maxCount          = b.maxCount;
            this.labels            = b.labels;
            this.taints            = b.taints;
        }

        public String getVmSize()                { return vmSize; }
        public int getNodeCount()                { return nodeCount; }
        public boolean isEnableAutoScaling()     { return enableAutoScaling; }
        public int getMinCount()                 { return minCount; }
        public int getMaxCount()                 { return maxCount; }
        public Map<String, String> getLabels()   { return labels; }
        public List<String> getTaints()          { return taints; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String vmSize = "Standard_D4s_v3";
            private int nodeCount = 2, minCount = 1, maxCount = 10;
            private boolean enableAutoScaling = false;
            private Map<String, String> labels = Map.of();
            private List<String> taints = List.of();

            public Builder vmSize(String v)                  { this.vmSize = v;            return this; }
            public Builder nodeCount(int v)                  { this.nodeCount = v;         return this; }
            public Builder enableAutoScaling(boolean v)      { this.enableAutoScaling = v; return this; }
            public Builder minCount(int v)                   { this.minCount = v;          return this; }
            public Builder maxCount(int v)                   { this.maxCount = v;          return this; }
            public Builder labels(Map<String, String> v)     { this.labels = v;            return this; }
            public Builder taints(List<String> v)            { this.taints = v;            return this; }
            public NodePoolConfig build() { return new NodePoolConfig(this); }
        }
    }


    // ── AksConfig ─────────────────────────────────────────────────────────────

    public static final class AksConfig {
        private final String kubernetesVersion, systemNodeVmSize, serviceCidr, dnsServiceIp;
        private final int systemNodeCount;
        private final Map<String, NodePoolConfig> additionalNodePools;
        private final List<String> adminGroupObjectIds;
        private final Map<String, String> extraTags;

        private AksConfig(Builder b) {
            this.kubernetesVersion    = b.kubernetesVersion;
            this.systemNodeVmSize     = b.systemNodeVmSize;
            this.systemNodeCount      = b.systemNodeCount;
            this.additionalNodePools  = b.additionalNodePools;
            this.adminGroupObjectIds  = b.adminGroupObjectIds;
            this.serviceCidr          = b.serviceCidr;
            this.dnsServiceIp         = b.dnsServiceIp;
            this.extraTags            = b.extraTags;
        }

        public String getKubernetesVersion()                      { return kubernetesVersion; }
        public String getSystemNodeVmSize()                       { return systemNodeVmSize; }
        public int getSystemNodeCount()                           { return systemNodeCount; }
        public Map<String, NodePoolConfig> getAdditionalNodePools(){ return additionalNodePools; }
        public List<String> getAdminGroupObjectIds()              { return adminGroupObjectIds; }
        public String getServiceCidr()                            { return serviceCidr; }
        public String getDnsServiceIp()                           { return dnsServiceIp; }
        public Map<String, String> getExtraTags()                 { return extraTags; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String kubernetesVersion = "1.29";
            private String systemNodeVmSize  = "Standard_D2s_v3";
            private int systemNodeCount = 3;
            private Map<String, NodePoolConfig> additionalNodePools = Map.of();
            private List<String> adminGroupObjectIds = List.of();
            private String serviceCidr  = "10.240.0.0/16";
            private String dnsServiceIp = "10.240.0.10";
            private Map<String, String> extraTags = Map.of();

            public Builder kubernetesVersion(String v)                       { this.kubernetesVersion = v;   return this; }
            public Builder systemNodeVmSize(String v)                        { this.systemNodeVmSize = v;    return this; }
            public Builder systemNodeCount(int v)                            { this.systemNodeCount = v;     return this; }
            public Builder additionalNodePools(Map<String, NodePoolConfig> v){ this.additionalNodePools = v; return this; }
            public Builder adminGroupObjectIds(List<String> v)               { this.adminGroupObjectIds = v; return this; }
            public Builder serviceCidr(String v)                             { this.serviceCidr = v;         return this; }
            public Builder dnsServiceIp(String v)                            { this.dnsServiceIp = v;        return this; }
            public Builder extraTags(Map<String, String> v)                  { this.extraTags = v;           return this; }
            public AksConfig build() { return new AksConfig(this); }
        }
    }


    // ── AksConstructProps ──────────────────────────────────────────────────────

    public static final class AksConstructProps {
        private final String project, environment, resourceGroup, location;
        private final String subnetId, logWorkspaceId;
        private final AksConfig config;

        private AksConstructProps(Builder b) {
            this.project        = b.project;
            this.environment    = b.environment;
            this.resourceGroup  = b.resourceGroup;
            this.location       = b.location;
            this.subnetId       = b.subnetId;
            this.logWorkspaceId = b.logWorkspaceId;
            this.config         = b.config;
        }

        public String getProject()        { return project; }
        public String getEnvironment()    { return environment; }
        public String getResourceGroup()  { return resourceGroup; }
        public String getLocation()       { return location; }
        public String getSubnetId()       { return subnetId; }
        public String getLogWorkspaceId() { return logWorkspaceId; }
        public AksConfig getConfig()      { return config; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String project, environment, resourceGroup, location;
            private String subnetId, logWorkspaceId;
            private AksConfig config;

            public Builder project(String v)        { this.project = v;        return this; }
            public Builder environment(String v)    { this.environment = v;    return this; }
            public Builder resourceGroup(String v)  { this.resourceGroup = v;  return this; }
            public Builder location(String v)       { this.location = v;       return this; }
            public Builder subnetId(String v)       { this.subnetId = v;       return this; }
            public Builder logWorkspaceId(String v) { this.logWorkspaceId = v; return this; }
            public Builder config(AksConfig v)      { this.config = v;         return this; }
            public AksConstructProps build() { return new AksConstructProps(this); }
        }
    }
}
