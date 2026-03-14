# Backend configuration for prod.
# OIDC service principal: portal-prod-tf (configured in GitHub Environment "prod")
# Azure subscription:     portal-prod  (AZURE_SUBSCRIPTION_ID in GitHub Environment "prod")

resource_group_name  = "platform-tfstate-rg"
storage_account_name = "platformtfstate"
container_name       = "tfstate"
key                  = "portal/prod/terraform.tfstate"
use_oidc             = true
