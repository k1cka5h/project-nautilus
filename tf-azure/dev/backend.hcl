# Backend configuration for dev.
# Loaded at init time: terraform -chdir=shared init -backend-config=../dev/backend.hcl
#
# OIDC service principal: portal-dev-tf (configured in GitHub Environment "dev")
# Azure subscription:     portal-dev  (AZURE_SUBSCRIPTION_ID in GitHub Environment "dev")

resource_group_name  = "platform-tfstate-rg"
storage_account_name = "platformtfstate"
container_name       = "tfstate"
key                  = "portal/dev/terraform.tfstate"
use_oidc             = true
