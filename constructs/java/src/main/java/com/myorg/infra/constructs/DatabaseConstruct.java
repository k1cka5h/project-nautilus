package com.myorg.infra.constructs;

import software.constructs.Construct;
import com.hashicorp.cdktf.TerraformModule;
import com.myorg.infra.policy.Tagging;

import java.util.*;

/**
 * Provisions an Azure PostgreSQL Flexible Server with private VNet access.
 * Wraps modules/database/postgres from the platform Terraform module repo.
 */
public class DatabaseConstruct extends Construct {

    private static final String MODULE_SOURCE =
        "git::ssh://git@github.com/myorg/terraform-modules.git" +
        "//modules/database/postgres?ref=v1.4.0";

    private final TerraformModule module;

    public DatabaseConstruct(Construct scope, String id, DatabaseConstructProps props) {
        super(scope, id);

        var cfg = props.getConfig() != null ? props.getConfig() : PostgresConfig.builder().build();

        var variables = new HashMap<String, Object>();
        variables.put("project",                props.getProject());
        variables.put("environment",            props.getEnvironment());
        variables.put("resource_group_name",    props.getResourceGroup());
        variables.put("location",               props.getLocation());
        variables.put("delegated_subnet_id",    props.getSubnetId());
        variables.put("private_dns_zone_id",    props.getDnsZoneId());
        variables.put("administrator_password", props.getAdminPassword());
        variables.put("databases",              cfg.getDatabases());
        variables.put("sku_name",               cfg.getSku());
        variables.put("storage_mb",             cfg.getStorageMb());
        variables.put("pg_version",             cfg.getPgVersion());
        variables.put("high_availability_mode", cfg.isHaEnabled() ? "ZoneRedundant" : "Disabled");
        variables.put("geo_redundant_backup",   cfg.isGeoRedundant());
        variables.put("server_configurations",  cfg.getServerConfigs());
        variables.put("tags",                   Tagging.requiredTags(props.getProject(), props.getEnvironment(), cfg.getExtraTags()));

        this.module = TerraformModule.Builder.create(this, "postgres")
                .source(MODULE_SOURCE)
                .variables(variables)
                .build();
    }

    /** FQDN for connecting to the server. Use as the connection host. */
    public String getFqdn()       { return module.getString("fqdn"); }
    public String getServerId()   { return module.getString("server_id"); }
    public String getServerName() { return module.getString("server_name"); }


    // ── PostgresConfig ────────────────────────────────────────────────────────

    public static final class PostgresConfig {
        private final List<String> databases;
        private final String sku, pgVersion;
        private final int storageMb;
        private final boolean haEnabled, geoRedundant;
        private final Map<String, String> serverConfigs, extraTags;

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

        public List<String> getDatabases()            { return databases; }
        public String getSku()                        { return sku; }
        public int getStorageMb()                     { return storageMb; }
        public String getPgVersion()                  { return pgVersion; }
        public boolean isHaEnabled()                  { return haEnabled; }
        public boolean isGeoRedundant()               { return geoRedundant; }
        public Map<String, String> getServerConfigs() { return serverConfigs; }
        public Map<String, String> getExtraTags()     { return extraTags; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private List<String> databases = List.of();
            private String sku = "GP_Standard_D2s_v3";
            private int storageMb = 32768;
            private String pgVersion = "15";
            private boolean haEnabled = false;
            private boolean geoRedundant = false;
            private Map<String, String> serverConfigs = Map.of();
            private Map<String, String> extraTags = Map.of();

            public Builder databases(List<String> v)          { this.databases = v;     return this; }
            public Builder sku(String v)                      { this.sku = v;           return this; }
            public Builder storageMb(int v)                   { this.storageMb = v;     return this; }
            public Builder pgVersion(String v)                { this.pgVersion = v;     return this; }
            public Builder haEnabled(boolean v)               { this.haEnabled = v;     return this; }
            public Builder geoRedundant(boolean v)            { this.geoRedundant = v;  return this; }
            public Builder serverConfigs(Map<String, String> v){ this.serverConfigs = v; return this; }
            public Builder extraTags(Map<String, String> v)   { this.extraTags = v;     return this; }
            public PostgresConfig build() { return new PostgresConfig(this); }
        }
    }


    // ── DatabaseConstructProps ─────────────────────────────────────────────────

    public static final class DatabaseConstructProps {
        private final String project, environment, resourceGroup, location;
        private final String subnetId, dnsZoneId, adminPassword;
        private final PostgresConfig config;

        private DatabaseConstructProps(Builder b) {
            this.project       = b.project;
            this.environment   = b.environment;
            this.resourceGroup = b.resourceGroup;
            this.location      = b.location;
            this.subnetId      = b.subnetId;
            this.dnsZoneId     = b.dnsZoneId;
            this.adminPassword = b.adminPassword;
            this.config        = b.config;
        }

        public String getProject()       { return project; }
        public String getEnvironment()   { return environment; }
        public String getResourceGroup() { return resourceGroup; }
        public String getLocation()      { return location; }
        public String getSubnetId()      { return subnetId; }
        public String getDnsZoneId()     { return dnsZoneId; }
        public String getAdminPassword() { return adminPassword; }
        public PostgresConfig getConfig(){ return config; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String project, environment, resourceGroup, location;
            private String subnetId, dnsZoneId, adminPassword;
            private PostgresConfig config;

            public Builder project(String v)         { this.project = v;       return this; }
            public Builder environment(String v)     { this.environment = v;   return this; }
            public Builder resourceGroup(String v)   { this.resourceGroup = v; return this; }
            public Builder location(String v)        { this.location = v;      return this; }
            public Builder subnetId(String v)        { this.subnetId = v;      return this; }
            public Builder dnsZoneId(String v)       { this.dnsZoneId = v;     return this; }
            public Builder adminPassword(String v)   { this.adminPassword = v; return this; }
            public Builder config(PostgresConfig v)  { this.config = v;        return this; }
            public DatabaseConstructProps build() { return new DatabaseConstructProps(this); }
        }
    }
}
