using Constructs;
using HashiCorp.Cdktf;
using HashiCorp.Cdktf.Providers.Azurerm.Provider;

namespace MyOrg.Infra;

public record BaseAzureStackProps(
    string Project,
    string Environment,
    string Location = "eastus");

/// <summary>
/// Base stack for all developer-authored CDKTF stacks.
/// Configures the AzureRM provider and remote state backend automatically.
/// </summary>
public class BaseAzureStack : TerraformStack
{
    public string Project     { get; }
    public string Environment { get; }
    public string Location    { get; }

    public BaseAzureStack(Construct scope, string id, BaseAzureStackProps props)
        : base(scope, id)
    {
        if (!new[] { "dev", "staging", "prod" }.Contains(props.Environment))
            throw new ArgumentException(
                $"Environment must be dev, staging, or prod — got '{props.Environment}'");

        Project     = props.Project;
        Environment = props.Environment;
        Location    = props.Location;

        new AzurermProvider(this, "azurerm", new AzurermProviderConfig
        {
            Features = [new AzurermProviderFeatures()],
        });

        new AzurermBackend(this, new AzurermBackendConfig
        {
            ResourceGroupName  = "platform-tfstate-rg",
            StorageAccountName = "platformtfstate",
            ContainerName      = "tfstate",
            Key                = $"{Project}/{Environment}/terraform.tfstate",
        });
    }
}
