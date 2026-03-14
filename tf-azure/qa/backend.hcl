# Backend configuration for QA.
# OIDC service principal: portal-qa-tf (configured in GitHub Environment "qa")
# Azure subscription:     portal-nonprod  (AZURE_SUBSCRIPTION_ID in GitHub Environment "qa")

resource_group_name  = "platform-tfstate-rg"
storage_account_name = "platformtfstate"
container_name       = "tfstate"
key                  = "portal/qa/terraform.tfstate"
use_oidc             = true
