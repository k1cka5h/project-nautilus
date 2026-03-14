# ── Network ─────────────────────────────────────────────────────────────────────

output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = module.network.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet name to resource ID."
  value       = module.network.subnet_ids
}

output "dns_zone_ids" {
  description = "Map of DNS zone name to resource ID."
  value       = module.network.dns_zone_ids
}

# ── Database ─────────────────────────────────────────────────────────────────────

output "postgres_fqdn" {
  description = "Fully-qualified domain name of the PostgreSQL server."
  value       = var.enable_database ? module.database[0].fqdn : null
}

output "postgres_server_id" {
  description = "Resource ID of the PostgreSQL server."
  value       = var.enable_database ? module.database[0].server_id : null
}

# ── AKS ─────────────────────────────────────────────────────────────────────────

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = var.enable_aks ? module.aks[0].cluster_id : null
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity. Used to grant ACR pull access."
  value       = var.enable_aks ? module.aks[0].kubelet_identity_object_id : null
}
