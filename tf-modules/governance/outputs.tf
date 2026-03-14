output "deny_public_resources_policy_id" {
  description = "Resource ID of the deny-public-resources policy definition."
  value       = azurerm_policy_definition.deny_public_resources.id
}

output "deny_network_write_policy_id" {
  description = "Resource ID of the deny-network-write-nonprod policy definition."
  value       = azurerm_policy_definition.deny_network_write_nonprod.id
}

output "deny_role_assignments_policy_id" {
  description = "Resource ID of the deny-role-assignments-nonprod policy definition."
  value       = azurerm_policy_definition.deny_role_assignments_nonprod.id
}
