# ── Identity ───────────────────────────────────────────────────────────────────
project     = "portal"
environment = "dev"
location    = "eastus"

# ── Resource Groups ─────────────────────────────────────────────────────────────
network_resource_group = "portal-dev-network-rg"
app_resource_group     = "portal-dev-app-rg"

# ── Networking ──────────────────────────────────────────────────────────────────
address_space = ["10.0.0.0/16"]

subnets = {
  aks = {
    address_prefix = "10.0.0.0/22"
  }
  db = {
    address_prefix    = "10.0.4.0/24"
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
postgres_sku                  = "B_Standard_B2ms"
postgres_storage_mb           = 32768
postgres_version              = "15"
postgres_ha_mode              = "Disabled"
postgres_geo_redundant_backup = false
postgres_databases            = ["portal"]

# administrator_password is supplied via TF_VAR_administrator_password (CI secret)

# ── AKS ────────────────────────────────────────────────────────────────────────
enable_aks          = true
kubernetes_version  = "1.29"
system_node_vm_size = "Standard_D2s_v3"
system_node_count   = 1   # single node acceptable in dev

additional_node_pools = {
  workers = {
    vm_size             = "Standard_D2s_v3"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 3
    labels              = { workload = "app" }
  }
}

# log_analytics_workspace_id supplied via TF_VAR_log_analytics_workspace_id (CI secret)

# ── Tagging ─────────────────────────────────────────────────────────────────────
extra_tags = {
  team        = "portal"
  cost_center = "engineering"
}
