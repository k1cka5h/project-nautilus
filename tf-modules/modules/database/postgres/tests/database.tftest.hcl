# Terraform module tests — database/postgres
# ============================================
# Uses terraform test (>= 1.7) with mock_provider so no Azure credentials
# are needed. Run with:
#   terraform test
# from the modules/database/postgres/ directory.

mock_provider "azurerm" {}

# ── shared variables ───────────────────────────────────────────────────────────

variables {
  project                = "test"
  environment            = "dev"
  resource_group_name    = "test-dev-app-rg"
  location               = "eastus"
  delegated_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-dev-rg/providers/Microsoft.Network/virtualNetworks/test-dev-vnet/subnets/db"
  private_dns_zone_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-dev-rg/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
  administrator_password = "TestPassword123!"
  databases              = ["appdb"]
  tags = {
    managed_by  = "terraform"
    project     = "test"
    environment = "dev"
  }
}

# ── naming convention ──────────────────────────────────────────────────────────

run "server_name_follows_convention" {
  assert {
    condition     = azurerm_postgresql_flexible_server.this.name == "test-dev-pg"
    error_message = "Server name must follow {project}-{environment}-pg"
  }
}

# ── database creation ──────────────────────────────────────────────────────────

run "creates_declared_databases" {
  assert {
    condition     = length(azurerm_postgresql_flexible_server_database.this) == 1
    error_message = "Expected 1 database resource (appdb)"
  }
}

run "creates_multiple_databases" {
  variables {
    databases = ["appdb", "analyticsdb", "auditdb"]
  }
  assert {
    condition     = length(azurerm_postgresql_flexible_server_database.this) == 3
    error_message = "Expected 3 database resources"
  }
}

# ── high availability ──────────────────────────────────────────────────────────

run "ha_disabled_by_default" {
  assert {
    condition     = length(azurerm_postgresql_flexible_server.this.high_availability) == 0
    error_message = "HA should be disabled when high_availability_mode=Disabled"
  }
}

run "ha_enabled_with_zone_redundant" {
  variables {
    high_availability_mode = "ZoneRedundant"
  }
  assert {
    condition     = length(azurerm_postgresql_flexible_server.this.high_availability) == 1
    error_message = "HA block must be present when high_availability_mode=ZoneRedundant"
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant"
    error_message = "HA mode must be ZoneRedundant"
  }
}

# ── server configuration overrides ────────────────────────────────────────────

run "applies_server_configuration_overrides" {
  variables {
    server_configurations = {
      "log_min_duration_statement" = "1000"
      "pg_qs.query_capture_mode"   = "ALL"
    }
  }
  assert {
    condition     = length(azurerm_postgresql_flexible_server_configuration.this) == 2
    error_message = "Expected 2 server configuration resources"
  }
}

run "no_server_configurations_by_default" {
  assert {
    condition     = length(azurerm_postgresql_flexible_server_configuration.this) == 0
    error_message = "No server config overrides should be created by default"
  }
}

# ── management locks ──────────────────────────────────────────────────────────

run "no_management_lock_in_dev" {
  assert {
    condition     = length(azurerm_management_lock.server) == 0
    error_message = "No management lock should be created in dev"
  }
}

run "management_lock_created_in_staging" {
  variables {
    environment = "staging"
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "staging"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.server) == 1
    error_message = "Management lock must be created in staging"
  }
  assert {
    condition     = azurerm_management_lock.server[0].lock_level == "CanNotDelete"
    error_message = "Lock level must be CanNotDelete"
  }
}

run "management_lock_created_in_prod" {
  variables {
    environment            = "prod"
    high_availability_mode = "ZoneRedundant"
    geo_redundant_backup   = true
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "prod"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.server) == 1
    error_message = "Management lock must be created in prod"
  }
}

# ── outputs ────────────────────────────────────────────────────────────────────

run "outputs_administrator_login" {
  assert {
    condition     = output.administrator_login == "pgadmin"
    error_message = "administrator_login output should be 'pgadmin'"
  }
}

run "outputs_database_ids_for_all_databases" {
  assert {
    condition     = contains(keys(output.database_ids), "appdb")
    error_message = "database_ids output must contain 'appdb'"
  }
}
