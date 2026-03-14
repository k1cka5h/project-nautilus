# Credentials are supplied by the CI/CD pipeline via environment variables.
# No static credentials are stored here.
#
# Required environment variables (set by GitHub Actions OIDC):
#   ARM_CLIENT_ID       — service principal client ID (per-environment)
#   ARM_TENANT_ID       — Azure AD tenant ID
#   ARM_SUBSCRIPTION_ID — target subscription (per-environment)
#   ARM_USE_OIDC        — "true" (enables GitHub Actions OIDC token exchange)
#
# For local development, use `az login` and omit ARM_USE_OIDC.
provider "azurerm" {
  features {}
}
