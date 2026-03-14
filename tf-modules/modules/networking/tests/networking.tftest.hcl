# Terraform module tests — networking
# =====================================
# Uses terraform test (>= 1.7) with mock_provider so no Azure credentials
# are needed. Run with:
#   terraform test
# from the modules/networking/ directory.

mock_provider "azurerm" {}

# ── shared variables ───────────────────────────────────────────────────────────

variables {
  project             = "test"
  environment         = "dev"
  resource_group_name = "test-dev-network-rg"
  location            = "eastus"
  address_space       = ["10.0.0.0/16"]
  subnets = {
    aks = {
      address_prefix    = "10.0.0.0/22"
      service_endpoints = []
      delegation        = null
      nsg_rules         = []
    }
    db = {
      address_prefix    = "10.0.4.0/24"
      service_endpoints = []
      delegation = {
        name    = "postgres"
        service = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
      nsg_rules = []
    }
  }
  private_dns_zones = ["privatelink.postgres.database.azure.com"]
  tags = {
    managed_by  = "terraform"
    project     = "test"
    environment = "dev"
  }
}

# ── naming convention ──────────────────────────────────────────────────────────

run "vnet_name_follows_convention" {
  assert {
    condition     = azurerm_virtual_network.this.name == "test-dev-vnet"
    error_message = "VNet name must follow {project}-{environment}-vnet"
  }
}

run "nsg_names_follow_convention" {
  assert {
    condition     = azurerm_network_security_group.this["aks"].name == "test-dev-aks-nsg"
    error_message = "NSG name must follow {project}-{environment}-{subnet}-nsg"
  }
}

# ── subnet and DNS zone creation ───────────────────────────────────────────────

run "creates_all_subnets" {
  assert {
    condition     = length(azurerm_subnet.this) == 2
    error_message = "Expected 2 subnets (aks + db)"
  }
}

run "creates_private_dns_zone" {
  assert {
    condition     = length(azurerm_private_dns_zone.this) == 1
    error_message = "Expected 1 private DNS zone"
  }
}

run "creates_dns_vnet_link" {
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == 1
    error_message = "Expected 1 DNS zone VNet link"
  }
}

# ── management locks — dev has none ───────────────────────────────────────────

run "no_management_lock_on_rg_in_dev" {
  assert {
    condition     = length(azurerm_management_lock.resource_group) == 0
    error_message = "Management locks must not be created in dev"
  }
}

run "no_management_lock_on_vnet_in_dev" {
  assert {
    condition     = length(azurerm_management_lock.vnet) == 0
    error_message = "Management locks must not be created in dev"
  }
}

# ── management locks — staging and prod have them ─────────────────────────────

run "rg_management_lock_created_in_staging" {
  variables {
    environment         = "staging"
    resource_group_name = "test-staging-network-rg"
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "staging"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.resource_group) == 1
    error_message = "Management lock must be created on resource group in staging"
  }
  assert {
    condition     = azurerm_management_lock.resource_group[0].lock_level == "CanNotDelete"
    error_message = "Lock level must be CanNotDelete"
  }
}

run "vnet_management_lock_created_in_prod" {
  variables {
    environment         = "prod"
    resource_group_name = "test-prod-network-rg"
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "prod"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.vnet) == 1
    error_message = "Management lock must be created on VNet in prod"
  }
}

# ── outputs ────────────────────────────────────────────────────────────────────

run "outputs_subnet_ids_for_all_subnets" {
  assert {
    condition     = contains(keys(output.subnet_ids), "aks")
    error_message = "subnet_ids output must contain 'aks'"
  }
  assert {
    condition     = contains(keys(output.subnet_ids), "db")
    error_message = "subnet_ids output must contain 'db'"
  }
}

run "outputs_nsg_ids_for_all_subnets" {
  assert {
    condition     = contains(keys(output.nsg_ids), "aks")
    error_message = "nsg_ids output must contain 'aks'"
  }
}

run "outputs_dns_zone_ids" {
  assert {
    condition     = contains(keys(output.dns_zone_ids), "privatelink.postgres.database.azure.com")
    error_message = "dns_zone_ids must contain the postgres private DNS zone"
  }
}
