from constructs import Construct
from cdktf import TerraformStack, AzurermBackend
from cdktf_cdktf_provider_azurerm.provider import AzurermProvider


class BaseAzureStack(TerraformStack):
    """Base stack for all developer-authored CDKTF stacks.

    Configures:
    - AzureRM provider (developers do not touch provider blocks)
    - Remote state in the platform-managed Blob Storage backend

    Parameters
    ----------
    scope       : CDKTF App instance
    id_         : Stack identifier
    project     : Short project/application name (e.g. 'myapp')
    environment : One of 'dev', 'staging', 'prod'
    location    : Azure region (default: 'eastus')
    """

    def __init__(
        self,
        scope: Construct,
        id_: str,
        *,
        project: str,
        environment: str,
        location: str = "eastus",
    ):
        super().__init__(scope, id_)

        if environment not in ("dev", "staging", "prod"):
            raise ValueError(f"environment must be dev, staging, or prod — got '{environment}'")

        self.project = project
        self.environment = environment
        self.location = location

        AzurermProvider(self, "azurerm", features=[{}])

        AzurermBackend(
            self,
            resource_group_name="platform-tfstate-rg",
            storage_account_name="platformtfstate",
            container_name="tfstate",
            key=f"{project}/{environment}/terraform.tfstate",
        )
