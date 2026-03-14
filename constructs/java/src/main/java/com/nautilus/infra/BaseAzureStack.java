package com.nautilus.infra;

import software.constructs.Construct;
import com.hashicorp.cdktf.TerraformStack;
import com.hashicorp.cdktf.AzurermBackend;
import com.hashicorp.cdktf.AzurermBackendConfig;
import com.hashicorp.cdktf.providers.azurerm.provider.AzurermProvider;
import com.hashicorp.cdktf.providers.azurerm.provider.AzurermProviderConfig;
import com.hashicorp.cdktf.providers.azurerm.provider.AzurermProviderFeatures;
import java.util.List;
import java.util.Set;

/**
 * Base stack for all developer-authored CDKTF stacks.
 * Configures the AzureRM provider and remote state backend automatically.
 */
public class BaseAzureStack extends TerraformStack {

    private final String project;
    private final String environment;
    private final String location;

    public BaseAzureStack(Construct scope, String id, BaseAzureStackProps props) {
        super(scope, id);

        if (!Set.of("dev", "staging", "prod").contains(props.getEnvironment())) {
            throw new IllegalArgumentException(
                "environment must be dev, staging, or prod — got '" + props.getEnvironment() + "'");
        }

        this.project     = props.getProject();
        this.environment = props.getEnvironment();
        this.location    = props.getLocation() != null ? props.getLocation() : "eastus";

        AzurermProvider.Builder.create(this, "azurerm")
                .features(List.of(AzurermProviderFeatures.builder().build()))
                .build();

        AzurermBackend.Builder.create(this)
                .resourceGroupName("platform-tfstate-rg")
                .storageAccountName("platformtfstate")
                .containerName("tfstate")
                .key(this.project + "/" + this.environment + "/terraform.tfstate")
                .build();
    }

    public String getProject()     { return project; }
    public String getEnvironment() { return environment; }
    public String getLocation()    { return location; }


    // ── Builder ───────────────────────────────────────────────────────────────

    public static final class BaseAzureStackProps {
        private final String project;
        private final String environment;
        private final String location;

        private BaseAzureStackProps(Builder b) {
            this.project     = b.project;
            this.environment = b.environment;
            this.location    = b.location;
        }

        public String getProject()     { return project; }
        public String getEnvironment() { return environment; }
        public String getLocation()    { return location; }

        public static Builder builder() { return new Builder(); }

        public static final class Builder {
            private String project;
            private String environment;
            private String location;

            public Builder project(String v)     { this.project = v;     return this; }
            public Builder environment(String v) { this.environment = v; return this; }
            public Builder location(String v)    { this.location = v;    return this; }
            public BaseAzureStackProps build()   { return new BaseAzureStackProps(this); }
        }
    }
}
