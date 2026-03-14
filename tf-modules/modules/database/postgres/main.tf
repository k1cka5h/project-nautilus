terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

locals {
  name_prefix    = "${var.project}-${var.environment}"
  server_name    = "${local.name_prefix}-pg"
  admin_username = "pgadmin"
}

# ── PostgreSQL Flexible Server ─────────────────────────────────────────────────

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = local.server_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.pg_version
  delegated_subnet_id    = var.delegated_subnet_id
  private_dns_zone_id    = var.private_dns_zone_id
  administrator_login    = local.admin_username
  administrator_password = var.administrator_password
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  geo_redundant_backup_enabled = var.geo_redundant_backup
  tags                   = var.tags

  dynamic "high_availability" {
    for_each = var.high_availability_mode != "Disabled" ? [1] : []
    content {
      mode = var.high_availability_mode
    }
  }

  lifecycle {
    # Password changes are applied outside of Terraform (key rotation workflow).
    ignore_changes = [administrator_password]
  }
}

# ── Databases ──────────────────────────────────────────────────────────────────

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = toset(var.databases)

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Server parameter overrides ─────────────────────────────────────────────────

resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = var.server_configurations

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

# ── Delete protection (non-dev) ─────────────────────────────────────────────────

resource "azurerm_management_lock" "server" {
  count      = var.environment != "dev" ? 1 : 0
  name       = "${local.name_prefix}-pg-lock"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Nautilus platform. Open a #platform-infra ticket to remove."
}
