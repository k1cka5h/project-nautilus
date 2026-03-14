package com.myorg.infra.constructs;

import software.constructs.Construct;
import com.hashicorp.cdktf.TerraformModule;
import com.hashicorp.cdktf.TerraformModuleConfig;
import com.myorg.infra.policy.Tagging;

import java.util.*;

/**
 * Provisions a VNet with subnets, NSGs, and private DNS zones.
 * Wraps modules/networking from the platform Terraform module repo.
 */
public class NetworkConstruct extends Construct {

    private static final String MODULE_SOURCE =
        "git::ssh://git@github.com/myorg/terraform-modules.git" +
        "//modules/networking?ref=v1.4.0";

    private final TerraformModule module;

    public NetworkConstruct(Construct scope, String id, NetworkConstructProps props) {
        super(scope, id);

        var subnets = new HashMap<String, Object>();
        for (var entry : props.getSubnets().entrySet()) {
            var cfg = entry.getValue();
            var s = new HashMap<String, Object>();
            s.put("address_prefix",    cfg.getAddressPrefix());
            s.put("service_endpoints", cfg.getServiceEndpoints());
            if (cfg.getDelegation() != null) {
                var d = cfg.getDelegation();
                s.put("delegation", Map.of(
                    "name",    d.getName(),
                    "service", d.getService(),
                    "actions", d.getActions()
                ));
            }
            if (!cfg.getNsgRules().isEmpty()) s.put("nsg_rules", cfg.getNsgRules());
            subnets.put(entry.getKey(), s);
        }

        var variables = new HashMap<String, Object>();
        variables.put("project",             props.getProject());
        variables.put("environment",         props.getEnvironment());
        variables.put("resource_group_name", props.getResourceGroup());
        variables.put("location",            props.getLocation());
        variables.put("address_space",       props.getAddressSpace());
        variables.put("subnets",             subnets);
        variables.put("private_dns_zones",   props.getPrivateDnsZones());
        variables.put("tags",                Tagging.requiredTags(props.getProject(), props.getEnvironment(), props.getExtraTags()));

        this.module = TerraformModule.Builder.create(this, "networking")
                .source(MODULE_SOURCE)
                .variables(variables)
                .build();
    }

    public String getVnetId()   { return module.getString("vnet_id"); }
    public String getVnetName() { return module.getString("vnet_name"); }

    /** Map of subnet name → subnet resource ID. */
    @SuppressWarnings("unchecked")
    public Map<String, String> getSubnetIds() {
        return (Map<String, String>) module.get("subnet_ids");
    }

    /** Map of DNS zone name → resource ID. */
    @SuppressWarnings("unchecked")
    public Map<String, String> getDnsZoneIds() {
        return (Map<String, String>) module.get("dns_zone_ids");
    }


    // ── Props + Config classes ────────────────────────────────────────────────

    public record SubnetDelegation(String getName, String getService, List<String> getActions) {
        public static Builder builder() { return new Builder(); }
        public static final class Builder {
            private String name, service;
            private List<String> actions = List.of();
            public Builder name(String v)            { this.name = v;    return this; }
            public Builder service(String v)         { this.service = v; return this; }
            public Builder actions(List<String> v)   { this.actions = v; return this; }
            public SubnetDelegation build() { return new SubnetDelegation(name, service, actions); }
        }
    }

    public static final class SubnetConfig {
        private final String addressPrefix;
        private final List<String> serviceEndpoints;
        private final SubnetDelegation delegation;
        private final List<Object> nsgRules;

        private SubnetConfig(Builder b) {
            this.addressPrefix    = b.addressPrefix;
            this.serviceEndpoints = b.serviceEndpoints;
            this.delegation       = b.delegation;
            this.nsgRules         = b.nsgRules;
        }

        public String getAddressPrefix()          { return addressPrefix; }
        public List<String> getServiceEndpoints() { return serviceEndpoints; }
        public SubnetDelegation getDelegation()   { return delegation; }
        public List<Object> getNsgRules()         { return nsgRules; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String addressPrefix;
            private List<String> serviceEndpoints = List.of();
            private SubnetDelegation delegation;
            private List<Object> nsgRules = List.of();

            public Builder addressPrefix(String v)             { this.addressPrefix = v;    return this; }
            public Builder serviceEndpoints(List<String> v)    { this.serviceEndpoints = v; return this; }
            public Builder delegation(SubnetDelegation v)      { this.delegation = v;       return this; }
            public Builder nsgRules(List<Object> v)            { this.nsgRules = v;         return this; }
            public SubnetConfig build() { return new SubnetConfig(this); }
        }
    }

    public static final class NetworkConstructProps {
        private final String project, environment, resourceGroup, location;
        private final List<String> addressSpace, privateDnsZones;
        private final Map<String, SubnetConfig> subnets;
        private final Map<String, String> extraTags;

        private NetworkConstructProps(Builder b) {
            this.project          = b.project;
            this.environment      = b.environment;
            this.resourceGroup    = b.resourceGroup;
            this.location         = b.location;
            this.addressSpace     = b.addressSpace;
            this.privateDnsZones  = b.privateDnsZones;
            this.subnets          = b.subnets;
            this.extraTags        = b.extraTags;
        }

        public String getProject()                          { return project; }
        public String getEnvironment()                      { return environment; }
        public String getResourceGroup()                    { return resourceGroup; }
        public String getLocation()                         { return location; }
        public List<String> getAddressSpace()               { return addressSpace; }
        public List<String> getPrivateDnsZones()            { return privateDnsZones; }
        public Map<String, SubnetConfig> getSubnets()       { return subnets; }
        public Map<String, String> getExtraTags()           { return extraTags; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String project, environment, resourceGroup, location;
            private List<String> addressSpace = List.of();
            private List<String> privateDnsZones = List.of();
            private Map<String, SubnetConfig> subnets = Map.of();
            private Map<String, String> extraTags = Map.of();

            public Builder project(String v)                        { this.project = v;         return this; }
            public Builder environment(String v)                    { this.environment = v;     return this; }
            public Builder resourceGroup(String v)                  { this.resourceGroup = v;   return this; }
            public Builder location(String v)                       { this.location = v;        return this; }
            public Builder addressSpace(List<String> v)             { this.addressSpace = v;    return this; }
            public Builder privateDnsZones(List<String> v)          { this.privateDnsZones = v; return this; }
            public Builder subnets(Map<String, SubnetConfig> v)     { this.subnets = v;         return this; }
            public Builder extraTags(Map<String, String> v)         { this.extraTags = v;       return this; }
            public NetworkConstructProps build() { return new NetworkConstructProps(this); }
        }
    }
}
