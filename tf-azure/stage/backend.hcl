# Backend configuration for stage.
# OIDC service principal: portal-stage-tf (configured in GitHub Environment "stage")
# Azure subscription:     portal-nonprod  (AZURE_SUBSCRIPTION_ID in GitHub Environment "stage")

resource_group_name  = "platform-tfstate-rg"
storage_account_name = "platformtfstate"
container_name       = "tfstate"
key                  = "portal/stage/terraform.tfstate"
use_oidc             = true
