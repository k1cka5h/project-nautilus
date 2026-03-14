# ── Identity ───────────────────────────────────────────────────────────────────
project     = "portal"
environment = "prod"
location    = "eastus"

# ── Resource Groups ─────────────────────────────────────────────────────────────
network_resource_group = "portal-prod-network-rg"
app_resource_group     = "portal-prod-app-rg"

# ── Networking ──────────────────────────────────────────────────────────────────
address_space = ["10.3.0.0/16"]

subnets = {
  aks = {
    address_prefix = "10.3.0.0/22"
  }
  db = {
    address_prefix    = "10.3.4.0/24"
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
postgres_sku                  = "GP_Standard_D8s_v3"
postgres_storage_mb           = 524288
postgres_version              = "15"
postgres_ha_mode              = "ZoneRedundant"
postgres_geo_redundant_backup = true
postgres_databases            = ["portal"]

postgres_server_configurations = {
  "log_min_duration_statement" = "500"
  "pg_qs.query_capture_mode"   = "TOP"
  "pgms_wait_sampling.query_capture_mode" = "ALL"
}

# ── AKS ────────────────────────────────────────────────────────────────────────
enable_aks          = true
kubernetes_version  = "1.29"
system_node_vm_size = "Standard_D4s_v3"
system_node_count   = 3   # 3 nodes for zone redundancy

additional_node_pools = {
  workers = {
    vm_size             = "Standard_D8s_v3"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 20
    labels              = { workload = "app" }
  }
  memory = {
    vm_size             = "Standard_E8s_v3"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 5
    labels              = { workload = "memory-intensive" }
    taints              = ["dedicated=memory:NoSchedule"]
  }
}

# ── Tagging ─────────────────────────────────────────────────────────────────────
extra_tags = {
  team        = "portal"
  cost_center = "engineering"
  criticality = "high"
}
