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

  # Intentionally local backend — this module creates the remote backend.
  # After first apply, you can optionally migrate state to the storage account
  # it creates by adding an azurerm backend block and running `terraform init -migrate-state`.
  backend "local" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.platform_subscription_id
}

provider "azuread" {}

# ── Resource group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "platform" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    managed_by  = "nautilus-bootstrap"
    environment = "platform"
  }
}

# ── Terraform state backend ────────────────────────────────────────────────────

resource "azurerm_storage_account" "tfstate" {
  name                            = var.state_storage_account_name
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # Shared access key must remain enabled — Terraform uses blob lease-based
  # state locking which requires storage account key authentication.
  shared_access_key_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = azurerm_resource_group.platform.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# Protect the state account itself from accidental deletion.
resource "azurerm_management_lock" "tfstate" {
  name       = "nautilus-tfstate-lock"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Terraform state backend. Remove only during planned decommission."
}

# ── Platform service principal ─────────────────────────────────────────────────
# Used by the platform team's own pipelines (governance deployment, bootstrap).

resource "azuread_application" "platform" {
  display_name = "nautilus-platform"
}

resource "azuread_service_principal" "platform" {
  client_id = azuread_application.platform.client_id
}

# OIDC federated credential — allows the Nautilus repo's main branch to
# authenticate as this SP when running governance or bootstrap pipelines.
resource "azuread_application_federated_identity_credential" "platform_main" {
  application_id = azuread_application.platform.id
  display_name   = "github-${var.github_org}-${var.github_repo}-main"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  audiences      = ["api://AzureADTokenExchange"]
}

# Contributor on the platform subscription — needed to deploy governance
# (Azure Policy definitions and assignments).
resource "azurerm_role_assignment" "platform_contributor" {
  scope                = "/subscriptions/${var.platform_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.platform.object_id
}

# Storage Blob Data Contributor on the state account — allows the platform SP
# to read and write any product team's state during incident response.
resource "azurerm_role_assignment" "platform_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.platform.object_id
}
