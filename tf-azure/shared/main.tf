# ── Networking ──────────────────────────────────────────────────────────────────
# Provisions the VNet, subnets, NSGs, and private DNS zones.
# Creates the network resource group.

module "network" {
  source = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/networking?ref=v1.4.0"

  project             = var.project
  environment         = var.environment
  resource_group_name = var.network_resource_group
  location            = var.location
  address_space       = var.address_space
  subnets             = var.subnets
  private_dns_zones   = var.private_dns_zones
  tags                = local.tags
}

# ── Database ────────────────────────────────────────────────────────────────────
# PostgreSQL Flexible Server with private access via delegated subnet.
# Skipped entirely when enable_database = false.

module "database" {
  source = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/database/postgres?ref=v1.4.0"
  count  = var.enable_database ? 1 : 0

  project                = var.project
  environment            = var.environment
  resource_group_name    = var.app_resource_group
  location               = var.location
  delegated_subnet_id    = module.network.subnet_ids["db"]
  private_dns_zone_id    = module.network.dns_zone_ids["privatelink.postgres.database.azure.com"]
  administrator_password = var.administrator_password
  sku_name               = var.postgres_sku
  storage_mb             = var.postgres_storage_mb
  pg_version             = var.postgres_version
  high_availability_mode = var.postgres_ha_mode
  geo_redundant_backup   = var.postgres_geo_redundant_backup
  databases              = var.postgres_databases
  server_configurations  = var.postgres_server_configurations
  tags                   = local.tags

  depends_on = [module.network]
}

# ── AKS ────────────────────────────────────────────────────────────────────────
# AKS cluster with Azure CNI, AAD RBAC, and OMS monitoring.
# Skipped entirely when enable_aks = false.

module "aks" {
  source = "git::ssh://git@github.com/k1cka5h/terraform-modules.git//modules/compute/aks?ref=v1.4.0"
  count  = var.enable_aks ? 1 : 0

  project                    = var.project
  environment                = var.environment
  resource_group_name        = var.app_resource_group
  location                   = var.location
  subnet_id                  = module.network.subnet_ids["aks"]
  log_analytics_workspace_id = var.log_analytics_workspace_id
  kubernetes_version         = var.kubernetes_version
  system_node_vm_size        = var.system_node_vm_size
  system_node_count          = var.system_node_count
  service_cidr               = var.aks_service_cidr
  dns_service_ip             = var.aks_dns_service_ip
  admin_group_object_ids     = var.aks_admin_group_object_ids
  additional_node_pools      = var.additional_node_pools
  tags                       = local.tags

  depends_on = [module.network]
}
