output "resource_group_id" {
  description = "Resource ID of the created resource group."
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet resource ID."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}

output "nsg_ids" {
  description = "Map of subnet name to NSG resource ID."
  value       = { for k, v in azurerm_network_security_group.this : k => v.id }
}

output "dns_zone_ids" {
  description = "Map of DNS zone name to private DNS zone resource ID."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}
