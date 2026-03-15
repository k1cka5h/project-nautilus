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
 * Provisions a PostgreSQL Flexible Server with private VNet access.
 *
 * <p>Delegates to the platform {@code modules/database/postgres} Terraform module via
 * Pulumi-Terraform interop. Terraform creates every Azure resource;
 * Pulumi reads the outputs.
 */
public class DatabaseComponent extends ComponentResource {

    private static final String MODULE_REPO     = "git::ssh://git@github.com/nautilus/terraform-modules.git";
    private static final String MODULE_VERSION  = "v1.0.0";
    private static final String POSTGRES_SOURCE = MODULE_REPO + "//modules/database/postgres?ref=" + MODULE_VERSION;
    private static final Set<String> VALID_ENVIRONMENTS = Set.of("dev", "staging", "prod");

    // ── Config types ────────────────────────────────────────────────────────

    public static final class PostgresConfig {
        public final List<String> databases;
        public final String sku;
        public final int storageMb;
        public final String pgVersion;
        public final boolean haEnabled;
        public final boolean geoRedundant;
        public final Map<String, String> serverConfigs;
        public final Map<String, String> extraTags;

        private PostgresConfig(Builder b) {
            this.databases     = b.databases;
            this.sku           = b.sku;
            this.storageMb     = b.storageMb;
            this.pgVersion     = b.pgVersion;
            this.haEnabled     = b.haEnabled;
            this.geoRedundant  = b.geoRedundant;
            this.serverConfigs = b.serverConfigs;
            this.extraTags     = b.extraTags;
        }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private List<String> databases     = List.of();
            private String sku                 = "GP_Standard_D2s_v3";
            private int storageMb              = 32768;
            private String pgVersion           = "15";
            private boolean haEnabled          = false;
            private boolean geoRedundant       = false;
            private Map<String, String> serverConfigs = Map.of();
            private Map<String, String> extraTags     = Map.of();

            public Builder databases(List<String> v)          { this.databases = v;      return this; }
            public Builder sku(String v)                       { this.sku = v;            return this; }
            public Builder storageMb(int v)                    { this.storageMb = v;      return this; }
            public Builder pgVersion(String v)                 { this.pgVersion = v;      return this; }
            public Builder haEnabled(boolean v)                { this.haEnabled = v;      return this; }
            public Builder geoRedundant(boolean v)             { this.geoRedundant = v;   return this; }
            public Builder serverConfigs(Map<String, String> v){ this.serverConfigs = v;  return this; }
            public Builder extraTags(Map<String, String> v)    { this.extraTags = v;      return this; }
            public PostgresConfig build()                       { return new PostgresConfig(this); }
        }
    }

    public static final class DatabaseComponentArgs {
        public final String project, environment, resourceGroup, location;
        public final String subnetId, dnsZoneId, adminPassword;
        public final PostgresConfig config;

        private DatabaseComponentArgs(Builder b) {
            this.project       = b.project;
            this.environment   = b.environment;
            this.resourceGroup = b.resourceGroup;
            this.location      = b.location;
            this.subnetId      = b.subnetId;
            this.dnsZoneId     = b.dnsZoneId;
            this.adminPassword = b.adminPassword;
            this.config        = b.config;
        }

        public static Builder builder(String project, String environment, String resourceGroup, String location,
                                      String subnetId, String dnsZoneId, String adminPassword) {
            return new Builder(project, environment, resourceGroup, location, subnetId, dnsZoneId, adminPassword);
        }

        public static final class Builder {
            private final String project, environment, resourceGroup, location, subnetId, dnsZoneId, adminPassword;
            private PostgresConfig config = PostgresConfig.builder().build();

            private Builder(String project, String environment, String resourceGroup, String location,
                            String subnetId, String dnsZoneId, String adminPassword) {
                this.project = project; this.environment = environment; this.resourceGroup = resourceGroup;
                this.location = location; this.subnetId = subnetId; this.dnsZoneId = dnsZoneId;
                this.adminPassword = adminPassword;
            }
            public Builder config(PostgresConfig v)  { this.config = v; return this; }
            public DatabaseComponentArgs build()      { return new DatabaseComponentArgs(this); }
        }
    }

    // ── Outputs ─────────────────────────────────────────────────────────────

    /** Fully-qualified domain name for client connections. */
    public final Output<String> fqdn;
    /** Resource ID of the flexible server. */
    public final Output<String> serverId;
    /** Name of the flexible server. */
    public final Output<String> serverName;

    // ── Constructor ──────────────────────────────────────────────────────────

    public DatabaseComponent(String name, DatabaseComponentArgs args) {
        this(name, args, null);
    }

    public DatabaseComponent(String name, DatabaseComponentArgs args, ComponentResourceOptions opts) {
        super("nautilus:database:DatabaseComponent", name, opts);

        if (!VALID_ENVIRONMENTS.contains(args.environment))
            throw new IllegalArgumentException(
                "environment must be one of " + new TreeSet<>(VALID_ENVIRONMENTS) + ", got \"" + args.environment + "\"");

        var cfg  = args.config;
        var tags = Tagging.requiredTags(args.project, args.environment, cfg.extraTags);

        var mod = new Module(name + "-postgres", ModuleArgs.builder()
            .source(POSTGRES_SOURCE)
            .variables(Map.of(
                "project",                args.project,
                "environment",            args.environment,
                "resource_group_name",    args.resourceGroup,
                "location",               args.location,
                "delegated_subnet_id",    args.subnetId,
                "private_dns_zone_id",    args.dnsZoneId,
                "administrator_password", args.adminPassword,
                "databases",              cfg.databases,
                "sku_name",               cfg.sku,
                "storage_mb",             cfg.storageMb,
                "pg_version",             cfg.pgVersion,
                "high_availability_mode", cfg.haEnabled ? "ZoneRedundant" : "Disabled",
                "geo_redundant_backup",   cfg.geoRedundant,
                "server_configurations",  cfg.serverConfigs,
                "tags",                   tags
            ))
            .build(),
            CustomResourceOptions.builder().parent(this).build()
        );

        this.fqdn       = mod.getOutput("fqdn");
        this.serverId   = mod.getOutput("server_id");
        this.serverName = mod.getOutput("server_name");

        this.registerOutputs(Map.of(
            "fqdn",       fqdn,
            "serverId",   serverId,
            "serverName", serverName
        ));
    }
}
