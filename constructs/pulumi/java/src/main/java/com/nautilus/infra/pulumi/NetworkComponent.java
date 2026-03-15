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
 * Provisions a VNet with subnets, NSGs, and private DNS zones.
 *
 * <p>Delegates to the platform {@code modules/networking} Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
public class NetworkComponent extends ComponentResource {

    private static final String MODULE_REPO    = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private static final String MODULE_VERSION = "v1.0.0";
    private static final String NETWORK_SOURCE = MODULE_REPO + "//modules/networking?ref=" + MODULE_VERSION;
    private static final Set<String> VALID_ENVIRONMENTS = Set.of("dev", "staging", "prod");

    // ── Config types ────────────────────────────────────────────────────────

    public record SubnetDelegation(String name, String service, List<String> actions) {}

    public static final class SubnetConfig {
        public final String addressPrefix;
        public final List<String> serviceEndpoints;
        public final SubnetDelegation delegation;
        public final List<Object> nsgRules;

        private SubnetConfig(Builder b) {
            this.addressPrefix    = b.addressPrefix;
            this.serviceEndpoints = b.serviceEndpoints;
            this.delegation       = b.delegation;
            this.nsgRules         = b.nsgRules;
        }

        public static Builder builder(String addressPrefix) { return new Builder(addressPrefix); }

        public static final class Builder {
            private final String addressPrefix;
            private List<String> serviceEndpoints = List.of();
            private SubnetDelegation delegation;
            private List<Object> nsgRules = List.of();

            private Builder(String addressPrefix) { this.addressPrefix = addressPrefix; }
            public Builder serviceEndpoints(List<String> v) { this.serviceEndpoints = v; return this; }
            public Builder delegation(SubnetDelegation v)   { this.delegation = v;       return this; }
            public Builder nsgRules(List<Object> v)         { this.nsgRules = v;         return this; }
            public SubnetConfig build()                     { return new SubnetConfig(this); }
        }
    }

    public static final class NetworkComponentArgs {
        public final String project, environment, resourceGroup, location;
        public final List<String> addressSpace;
        public final Map<String, SubnetConfig> subnets;
        public final List<String> privateDnsZones;
        public final Map<String, String> extraTags;

        private NetworkComponentArgs(Builder b) {
            this.project        = b.project;
            this.environment    = b.environment;
            this.resourceGroup  = b.resourceGroup;
            this.location       = b.location;
            this.addressSpace   = b.addressSpace;
            this.subnets        = b.subnets;
            this.privateDnsZones = b.privateDnsZones;
            this.extraTags      = b.extraTags;
        }

        public static Builder builder(String project, String environment, String resourceGroup, String location) {
            return new Builder(project, environment, resourceGroup, location);
        }

        public static final class Builder {
            private final String project, environment, resourceGroup, location;
            private List<String> addressSpace = List.of();
            private Map<String, SubnetConfig> subnets = Map.of();
            private List<String> privateDnsZones = List.of();
            private Map<String, String> extraTags = Map.of();

            private Builder(String project, String environment, String resourceGroup, String location) {
                this.project = project; this.environment = environment;
                this.resourceGroup = resourceGroup; this.location = location;
            }
            public Builder addressSpace(List<String> v)              { this.addressSpace = v;   return this; }
            public Builder subnets(Map<String, SubnetConfig> v)      { this.subnets = v;        return this; }
            public Builder privateDnsZones(List<String> v)           { this.privateDnsZones = v; return this; }
            public Builder extraTags(Map<String, String> v)          { this.extraTags = v;      return this; }
            public NetworkComponentArgs build()                       { return new NetworkComponentArgs(this); }
        }
    }

    // ── Outputs ─────────────────────────────────────────────────────────────

    /** Resource ID of the VNet. */
    public final Output<String> vnetId;
    /** Name of the VNet. */
    public final Output<String> vnetName;
    /** Map of subnet name → resource ID. */
    public final Output<Map<String, String>> subnetIds;
    /** Map of DNS zone name → resource ID. */
    public final Output<Map<String, String>> dnsZoneIds;

    // ── Constructor ──────────────────────────────────────────────────────────

    public NetworkComponent(String name, NetworkComponentArgs args) {
        this(name, args, null);
    }

    public NetworkComponent(String name, NetworkComponentArgs args, ComponentResourceOptions opts) {
        super("nautilus:network:NetworkComponent", name, opts);

        if (!VALID_ENVIRONMENTS.contains(args.environment))
            throw new IllegalArgumentException(
                "environment must be one of " + new TreeSet<>(VALID_ENVIRONMENTS) + ", got \"" + args.environment + "\"");

        var tags = Tagging.requiredTags(args.project, args.environment, args.extraTags);

        // Serialise subnets to plain Map for Terraform module variables
        var subnetsMap = new LinkedHashMap<String, Object>();
        for (var entry : args.subnets.entrySet()) {
            var cfg = entry.getValue();
            var s = new LinkedHashMap<String, Object>();
            s.put("address_prefix", cfg.addressPrefix);
            if (!cfg.serviceEndpoints.isEmpty()) s.put("service_endpoints", cfg.serviceEndpoints);
            if (cfg.delegation != null) s.put("delegation", Map.of(
                "name", cfg.delegation.name(), "service", cfg.delegation.service(), "actions", cfg.delegation.actions()
            ));
            if (!cfg.nsgRules.isEmpty()) s.put("nsg_rules", cfg.nsgRules);
            subnetsMap.put(entry.getKey(), s);
        }

        var mod = new Module(name + "-networking", ModuleArgs.builder()
            .source(NETWORK_SOURCE)
            .variables(Map.of(
                "project",             args.project,
                "environment",         args.environment,
                "resource_group_name", args.resourceGroup,
                "location",            args.location,
                "address_space",       args.addressSpace,
                "subnets",             subnetsMap,
                "private_dns_zones",   args.privateDnsZones,
                "tags",                tags
            ))
            .build(),
            CustomResourceOptions.builder().parent(this).build()
        );

        this.vnetId     = mod.getOutput("vnet_id");
        this.vnetName   = mod.getOutput("vnet_name");
        this.subnetIds  = mod.getOutput("subnet_ids");
        this.dnsZoneIds = mod.getOutput("dns_zone_ids");

        this.registerOutputs(Map.of(
            "vnetId",     vnetId,
            "vnetName",   vnetName,
            "subnetIds",  subnetIds,
            "dnsZoneIds", dnsZoneIds
        ));
    }
}
