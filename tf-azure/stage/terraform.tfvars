# ── Identity ───────────────────────────────────────────────────────────────────
project     = "portal"
environment = "stage"
location    = "eastus"

# ── Resource Groups ─────────────────────────────────────────────────────────────
network_resource_group = "portal-stage-network-rg"
app_resource_group     = "portal-stage-app-rg"

# ── Networking ──────────────────────────────────────────────────────────────────
address_space = ["10.2.0.0/16"]

subnets = {
  aks = {
    address_prefix = "10.2.0.0/22"
  }
  db = {
    address_prefix    = "10.2.4.0/24"
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
postgres_sku                  = "GP_Standard_D4s_v3"
postgres_storage_mb           = 131072
postgres_version              = "15"
postgres_ha_mode              = "ZoneRedundant"
postgres_geo_redundant_backup = false
postgres_databases            = ["portal"]

postgres_server_configurations = {
  "log_min_duration_statement" = "1000"
  "pg_qs.query_capture_mode"   = "TOP"
}

# ── AKS ────────────────────────────────────────────────────────────────────────
enable_aks          = true
kubernetes_version  = "1.29"
system_node_vm_size = "Standard_D4s_v3"
system_node_count   = 3

additional_node_pools = {
  workers = {
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 10
    labels              = { workload = "app" }
  }
}

# ── Tagging ─────────────────────────────────────────────────────────────────────
extra_tags = {
  team        = "portal"
  cost_center = "engineering"
}
