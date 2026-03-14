terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
  }

  # Use the remote state backend created by bootstrap/platform.
  backend "azurerm" {
    # Values supplied via -backend-config at init time:
    #   storage_account_name = "platformtfstate"
    #   container_name       = "tfstate"
    #   key                  = "bootstrap/<product>/terraform.tfstate"
    #   use_oidc             = true
  }
}

provider "azurerm" {
  features {}
  # Authenticates using the platform SP (OIDC) or the operator's personal credentials.
  # No subscription_id set here — role assignments are scoped via their full resource IDs.
  subscription_id = var.platform_subscription_id
}

provider "azuread" {}

locals {
  environments = ["dev", "qa", "stage", "prod"]
}

# ── AAD application + service principal per environment ───────────────────────
# One SP per environment so that RBAC can be scoped to the correct subscription
# and the blast radius of a compromised credential is limited to one environment.

resource "azuread_application" "this" {
  for_each     = toset(local.environments)
  display_name = "${var.product_name}-${each.key}"
}

resource "azuread_service_principal" "this" {
  for_each  = azuread_application.this
  client_id = each.value.client_id
}

# ── OIDC federated credentials ────────────────────────────────────────────────
# Allows GitHub Actions jobs running in the named environment to exchange an
# OIDC token for an Azure access token — no stored secrets required.

resource "azuread_application_federated_identity_credential" "this" {
  for_each = azuread_application.this

  application_id = each.value.id
  display_name   = "github-${var.github_org}-${var.github_repo}-${each.key}"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
}

# ── RBAC — Contributor on each environment's subscription ─────────────────────
# Scoped to the target subscription for each environment. The resource ID path
# includes the subscription ID so the AzureRM provider makes the correct ARM call
# regardless of which subscription the provider is authenticated to.

resource "azurerm_role_assignment" "contributor" {
  for_each = var.subscription_ids

  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.this[each.key].object_id
}

# ── RBAC — Storage Blob Data Contributor on the state account ─────────────────
# Allows each environment's SP to read and write its own state blob.
# The assignment is at the storage account level (not container or blob level —
# Azure RBAC does not support blob-level scoping).

resource "azurerm_role_assignment" "state" {
  for_each = var.subscription_ids

  scope                = var.state_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.this[each.key].object_id
}
