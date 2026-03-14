# ── Identity ───────────────────────────────────────────────────────────────────
project     = "portal"
environment = "qa"
location    = "eastus"

# ── Resource Groups ─────────────────────────────────────────────────────────────
network_resource_group = "portal-qa-network-rg"
app_resource_group     = "portal-qa-app-rg"

# ── Networking ──────────────────────────────────────────────────────────────────
address_space = ["10.1.0.0/16"]

subnets = {
  aks = {
    address_prefix = "10.1.0.0/22"
  }
  db = {
    address_prefix    = "10.1.4.0/24"
    service_endpoints = ["Microsoft.Storage"]
    delegation = {
      name    = "postgres"
      service = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

private_dns_zones = ["privatelink.postgres.database.azure.com"]

# ── Database ────────────────────────────────────────────────────────────────────
enable_database               = true
postgres_sku                  = "GP_Standard_D2s_v3"
postgres_storage_mb           = 65536
postgres_version              = "15"
postgres_ha_mode              = "Disabled"
postgres_geo_redundant_backup = false
postgres_databases            = ["portal"]

# ── AKS ────────────────────────────────────────────────────────────────────────
enable_aks          = true
kubernetes_version  = "1.29"
system_node_vm_size = "Standard_D4s_v3"
system_node_count   = 2

additional_node_pools = {
  workers = {
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 6
    labels              = { workload = "app" }
  }
}

# ── Tagging ─────────────────────────────────────────────────────────────────────
extra_tags = {
  team        = "portal"
  cost_center = "engineering"
}
