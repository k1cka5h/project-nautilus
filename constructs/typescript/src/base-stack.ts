import { Construct } from "constructs";
import { TerraformStack, AzurermBackend } from "cdktf";
import { AzurermProvider } from "@cdktf/provider-azurerm/lib/provider";

export interface BaseAzureStackProps {
  readonly project:     string;
  readonly environment: string;
  readonly location?:   string;
}

export class BaseAzureStack extends TerraformStack {
  readonly project:     string;
  readonly environment: string;
  readonly location:    string;

  constructor(scope: Construct, id: string, props: BaseAzureStackProps) {
    super(scope, id);

    if (!["dev", "staging", "prod"].includes(props.environment)) {
      throw new Error(
        `environment must be dev, staging, or prod — got '${props.environment}'`,
      );
    }

    this.project     = props.project;
    this.environment = props.environment;
    this.location    = props.location ?? "eastus";

    new AzurermProvider(this, "azurerm", { features: [{}] });

    new AzurermBackend(this, {
      resourceGroupName:  "platform-tfstate-rg",
      storageAccountName: "platformtfstate",
      containerName:      "tfstate",
      key:                `${this.project}/${this.environment}/terraform.tfstate`,
    });
  }
}
