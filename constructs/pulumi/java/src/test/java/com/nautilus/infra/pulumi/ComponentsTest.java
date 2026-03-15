package com.nautilus.infra.pulumi;

import com.nautilus.infra.pulumi.policy.Tagging;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Component unit tests — Java
 * ============================
 * Validates component configuration wiring and tag policy.
 * Tests that exercise runtime resource creation would require a Pulumi mock
 * provider; validation tests here focus on construction-time checks which
 * do not require Azure credentials.
 *
 * Run:
 *   mvn test
 */
class ComponentsTest {

    // ── Tagging ────────────────────────────────────────────────────────────────

    @Test
    void tagging_requiredTagsContainsMandatoryKeys() {
        var tags = Tagging.requiredTags("myapp", "dev");
        assertEquals("pulumi",  tags.get("managed_by"));
        assertEquals("myapp",   tags.get("project"));
        assertEquals("dev",     tags.get("environment"));
    }

    @Test
    void tagging_requiredTagsOverrideExtra() {
        var extra = Map.of("managed_by", "manual", "team", "platform");
        var tags  = Tagging.requiredTags("myapp", "prod", extra);
        assertEquals("pulumi",   tags.get("managed_by"),
            "required tag managed_by must override extra");
        assertEquals("platform", tags.get("team"));
    }

    @Test
    void tagging_extraKeysIncluded() {
        var tags = Tagging.requiredTags("svc", "staging", Map.of("cost_center", "eng"));
        assertEquals("eng", tags.get("cost_center"));
    }


    // ── NetworkComponent props and validation ──────────────────────────────────

    @Test
    void network_throwsOnInvalidEnvironment() {
        assertThrows(IllegalArgumentException.class, () ->
            new NetworkComponent("net",
                NetworkComponent.NetworkComponentProps.builder()
                    .project("myapp").environment("uat")
                    .resourceGroup("rg").location("eastus")
                    .addressSpace(List.of("10.0.0.0/16"))
                    .build(),
                null));
    }

    @Test
    void network_subnetDelegationBuilder() {
        var deleg = NetworkComponent.SubnetDelegation.builder()
            .name("postgres")
            .service("Microsoft.DBforPostgreSQL/flexibleServers")
            .actions(List.of("Microsoft.Network/virtualNetworks/subnets/join/action"))
            .build();
        assertEquals("Microsoft.DBforPostgreSQL/flexibleServers", deleg.getService());
        assertEquals(1, deleg.getActions().size());
    }

    @Test
    void network_subnetConfigBuilder() {
        var cfg = NetworkComponent.SubnetConfig.builder()
            .addressPrefix("10.0.0.0/24")
            .serviceEndpoints(List.of("Microsoft.ContainerRegistry"))
            .build();
        assertEquals("10.0.0.0/24", cfg.getAddressPrefix());
        assertEquals(1, cfg.getServiceEndpoints().size());
    }


    // ── DatabaseComponent props and validation ─────────────────────────────────

    @Test
    void database_throwsOnInvalidEnvironment() {
        assertThrows(IllegalArgumentException.class, () ->
            new DatabaseComponent("db",
                DatabaseComponent.DatabaseComponentProps.builder()
                    .project("myapp").environment("qa")
                    .resourceGroup("rg").location("eastus")
                    .subnetId("sn").dnsZoneId("dns")
                    .adminPassword("secret")
                    .build(),
                null));
    }

    @Test
    void database_defaultConfigValues() {
        var cfg = DatabaseComponent.PostgresConfig.builder().build();
        assertFalse(cfg.isHaEnabled());
        assertEquals("GP_Standard_D2s_v3", cfg.getSku());
        assertEquals(32, cfg.getStorageGb());
        assertEquals("15", cfg.getPgVersion());
        assertFalse(cfg.isGeoRedundant());
    }

    @Test
    void database_haEnabledFlagSet() {
        var cfg = DatabaseComponent.PostgresConfig.builder()
            .haEnabled(true)
            .databases(List.of("appdb"))
            .build();
        assertTrue(cfg.isHaEnabled());
        assertTrue(cfg.getDatabases().contains("appdb"));
    }


    // ── AksComponent props and validation ─────────────────────────────────────

    @Test
    void aks_throwsOnInvalidEnvironment() {
        assertThrows(IllegalArgumentException.class, () ->
            new AksComponent("aks",
                AksComponent.AksComponentProps.builder()
                    .project("myapp").environment("badenv")
                    .resourceGroup("rg").location("eastus")
                    .subnetId("sn").logWorkspaceId("ws")
                    .build(),
                null));
    }

    @Test
    void aks_defaultConfigValues() {
        var cfg = AksComponent.AksConfig.builder().build();
        assertEquals("1.29",            cfg.getKubernetesVersion());
        assertEquals("Standard_D2s_v3", cfg.getSystemNodeVmSize());
        assertEquals(3,                 cfg.getSystemNodeCount());
        assertEquals("10.240.0.0/16",   cfg.getServiceCidr());
        assertEquals("10.240.0.10",     cfg.getDnsServiceIp());
    }

    @Test
    void aks_nodePoolConfigDefaults() {
        var pool = AksComponent.NodePoolConfig.builder().build();
        assertEquals("Standard_D4s_v3", pool.getVmSize());
        assertEquals(2,  pool.getNodeCount());
        assertFalse(pool.isEnableAutoScaling());
        assertEquals(1,  pool.getMinCount());
        assertEquals(10, pool.getMaxCount());
    }

    @Test
    void aks_additionalNodePoolBuilder() {
        var pool = AksComponent.NodePoolConfig.builder()
            .vmSize("Standard_D8s_v3")
            .enableAutoScaling(true)
            .minCount(2).maxCount(10)
            .labels(Map.of("workload", "app"))
            .build();
        assertEquals("Standard_D8s_v3", pool.getVmSize());
        assertTrue(pool.isEnableAutoScaling());
        assertEquals(2, pool.getMinCount());
        assertEquals("app", pool.getLabels().get("workload"));
    }
}
