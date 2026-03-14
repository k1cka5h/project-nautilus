package com.k1cka5h.infra;

import com.hashicorp.cdktf.App;
import com.hashicorp.cdktf.Testing;
import com.hashicorp.cdktf.TerraformStack;
import com.k1cka5h.infra.constructs.AksConstruct;
import com.k1cka5h.infra.constructs.DatabaseConstruct;
import com.k1cka5h.infra.constructs.NetworkConstruct;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Construct unit tests — Java
 * ============================
 * Synthesizes each construct to JSON and asserts the module call is wired
 * correctly. Does not run Terraform or touch Azure.
 *
 * Run:
 *   mvn test
 */
class ConstructsTest {

    // ── helpers ────────────────────────────────────────────────────────────────

    /** Plain TerraformStack for constructs that don't need a full BaseAzureStack. */
    private static TerraformStack plainStack() {
        App app = Testing.app();
        return new TerraformStack(app, "test-stack");
    }

    /** Synthesize a stack to JSON (returned as String). */
    private static String synth(TerraformStack stack) {
        return Testing.synthScope(stack);
    }


    // ── BaseAzureStack ─────────────────────────────────────────────────────────

    @Test
    void baseStack_setsCorrectStateKey() {
        App app = Testing.app();
        BaseAzureStack stack = new BaseAzureStack(app, "base",
                BaseAzureStack.BaseAzureStackProps.builder()
                        .project("proj")
                        .environment("dev")
                        .build());

        String json = Testing.synthScope(stack);
        assertTrue(json.contains("\"proj/dev/terraform.tfstate\""),
                "state key should be proj/dev/terraform.tfstate");
    }

    @Test
    void baseStack_defaultLocationIsEastUs() {
        App app = Testing.app();
        BaseAzureStack stack = new BaseAzureStack(app, "base2",
                BaseAzureStack.BaseAzureStackProps.builder()
                        .project("proj")
                        .environment("staging")
                        .build());

        assertEquals("eastus", stack.getLocation());
    }

    @Test
    void baseStack_throwsOnInvalidEnvironment() {
        App app = Testing.app();
        assertThrows(IllegalArgumentException.class, () ->
                new BaseAzureStack(app, "bad",
                        BaseAzureStack.BaseAzureStackProps.builder()
                                .project("proj")
                                .environment("uat")
                                .build()));
    }


    // ── NetworkConstruct ───────────────────────────────────────────────────────

    @Test
    void network_moduleSourceIsPinned() {
        TerraformStack stack = plainStack();
        new NetworkConstruct(stack, "net",
                NetworkConstruct.NetworkConstructProps.builder()
                        .project("myapp")
                        .environment("dev")
                        .resourceGroup("myapp-dev-rg")
                        .location("eastus")
                        .addressSpace(List.of("10.0.0.0/16"))
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("ref=v"),
                "module source should pin a ref tag");
        assertTrue(json.contains("modules/networking"),
                "module source should reference modules/networking");
    }

    @Test
    void network_requiredTagsInjected() {
        TerraformStack stack = plainStack();
        new NetworkConstruct(stack, "net",
                NetworkConstruct.NetworkConstructProps.builder()
                        .project("myapp")
                        .environment("staging")
                        .resourceGroup("myapp-staging-rg")
                        .location("eastus")
                        .addressSpace(List.of("10.0.0.0/16"))
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("\"managed_by\""),   "tags should contain managed_by");
        assertTrue(json.contains("\"terraform\""),    "managed_by value should be terraform");
        assertTrue(json.contains("\"myapp\""),         "tags should contain project=myapp");
        assertTrue(json.contains("\"staging\""),       "tags should contain environment=staging");
    }

    @Test
    void network_subnetDelegationSerialized() {
        TerraformStack stack = plainStack();
        new NetworkConstruct(stack, "net",
                NetworkConstruct.NetworkConstructProps.builder()
                        .project("myapp")
                        .environment("dev")
                        .resourceGroup("myapp-dev-rg")
                        .location("eastus")
                        .addressSpace(List.of("10.0.0.0/16"))
                        .subnets(Map.of(
                                "db", NetworkConstruct.SubnetConfig.builder()
                                        .addressPrefix("10.0.8.0/24")
                                        .delegation(NetworkConstruct.SubnetDelegation.builder()
                                                .name("postgres")
                                                .service("Microsoft.DBforPostgreSQL/flexibleServers")
                                                .actions(List.of("Microsoft.Network/virtualNetworks/subnets/join/action"))
                                                .build())
                                        .build()))
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("Microsoft.DBforPostgreSQL/flexibleServers"),
                "subnet delegation service should appear in synth output");
    }


    // ── DatabaseConstruct ──────────────────────────────────────────────────────

    @Test
    void database_moduleSourceIsPinned() {
        TerraformStack stack = plainStack();
        new DatabaseConstruct(stack, "db",
                DatabaseConstruct.DatabaseConstructProps.builder()
                        .project("myapp")
                        .environment("prod")
                        .resourceGroup("myapp-prod-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/db")
                        .dnsZoneId("/subscriptions/x/privateDnsZones/postgres.database.azure.com")
                        .adminPassword("Hunter2!")
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("ref=v"),               "module source should pin a ref tag");
        assertTrue(json.contains("modules/database/postgres"), "source should reference postgres module");
    }

    @Test
    void database_haEnabledSetsZoneRedundant() {
        TerraformStack stack = plainStack();
        new DatabaseConstruct(stack, "db",
                DatabaseConstruct.DatabaseConstructProps.builder()
                        .project("myapp")
                        .environment("prod")
                        .resourceGroup("myapp-prod-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/db")
                        .dnsZoneId("/subscriptions/x/privateDnsZones/postgres.database.azure.com")
                        .adminPassword("Hunter2!")
                        .config(DatabaseConstruct.PostgresConfig.builder()
                                .haEnabled(true)
                                .databases(List.of("appdb"))
                                .build())
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("\"ZoneRedundant\""),
                "HA enabled should set high_availability_mode=ZoneRedundant");
    }

    @Test
    void database_haDisabledSetsDisabled() {
        TerraformStack stack = plainStack();
        new DatabaseConstruct(stack, "db",
                DatabaseConstruct.DatabaseConstructProps.builder()
                        .project("myapp")
                        .environment("dev")
                        .resourceGroup("myapp-dev-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/db")
                        .dnsZoneId("/subscriptions/x/privateDnsZones/postgres.database.azure.com")
                        .adminPassword("Hunter2!")
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("\"Disabled\""),
                "HA disabled should set high_availability_mode=Disabled");
    }

    @Test
    void database_adminPasswordForwarded() {
        TerraformStack stack = plainStack();
        new DatabaseConstruct(stack, "db",
                DatabaseConstruct.DatabaseConstructProps.builder()
                        .project("myapp")
                        .environment("dev")
                        .resourceGroup("myapp-dev-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/db")
                        .dnsZoneId("/subscriptions/x/privateDnsZones/postgres.database.azure.com")
                        .adminPassword("MySecret123!")
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("administrator_password"),
                "administrator_password variable should appear in module variables");
    }


    // ── AksConstruct ──────────────────────────────────────────────────────────

    @Test
    void aks_moduleSourceIsPinned() {
        TerraformStack stack = plainStack();
        new AksConstruct(stack, "aks",
                AksConstruct.AksConstructProps.builder()
                        .project("myapp")
                        .environment("dev")
                        .resourceGroup("myapp-dev-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/aks")
                        .logWorkspaceId("/subscriptions/x/workspaces/logs")
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("ref=v"),             "module source should pin a ref tag");
        assertTrue(json.contains("modules/compute/aks"), "source should reference aks module");
    }

    @Test
    void aks_additionalNodePoolForwarded() {
        TerraformStack stack = plainStack();
        new AksConstruct(stack, "aks",
                AksConstruct.AksConstructProps.builder()
                        .project("myapp")
                        .environment("staging")
                        .resourceGroup("myapp-staging-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/aks")
                        .logWorkspaceId("/subscriptions/x/workspaces/logs")
                        .config(AksConstruct.AksConfig.builder()
                                .systemNodeCount(3)
                                .additionalNodePools(Map.of(
                                        "workers", AksConstruct.NodePoolConfig.builder()
                                                .vmSize("Standard_D8s_v3")
                                                .enableAutoScaling(true)
                                                .minCount(2)
                                                .maxCount(10)
                                                .build()))
                                .build())
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("\"workers\""),         "worker pool name should appear in synth");
        assertTrue(json.contains("Standard_D8s_v3"),     "worker pool vm_size should appear in synth");
        assertTrue(json.contains("enable_auto_scaling"),  "auto scaling config should be present");
    }

    @Test
    void aks_requiredTagsInjected() {
        TerraformStack stack = plainStack();
        new AksConstruct(stack, "aks",
                AksConstruct.AksConstructProps.builder()
                        .project("myapp")
                        .environment("prod")
                        .resourceGroup("myapp-prod-rg")
                        .location("eastus")
                        .subnetId("/subscriptions/x/subnets/aks")
                        .logWorkspaceId("/subscriptions/x/workspaces/logs")
                        .build());

        String json = synth(stack);
        assertTrue(json.contains("\"managed_by\""), "tags should contain managed_by");
        assertTrue(json.contains("\"terraform\""),  "managed_by should be terraform");
        assertTrue(json.contains("\"prod\""),        "tags should contain environment=prod");
    }
}
