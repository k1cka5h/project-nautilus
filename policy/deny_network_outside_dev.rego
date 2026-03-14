package nautilus.deny_network_outside_dev

import future.keywords.in

# Network resource types that developers may only create in dev.
# In staging and prod, network infrastructure is centrally managed by the
# platform team and referenced via data sources — not provisioned by developer stacks.
network_resource_types := {
  "azurerm_virtual_network",
  "azurerm_subnet",
  "azurerm_network_security_group",
  "azurerm_network_security_rule",
  "azurerm_subnet_network_security_group_association",
  "azurerm_route_table",
  "azurerm_subnet_route_table_association",
  "azurerm_private_dns_zone",
  "azurerm_private_dns_zone_virtual_network_link",
  "azurerm_private_endpoint",
  "azurerm_virtual_network_gateway",
  "azurerm_local_network_gateway",
  "azurerm_virtual_network_gateway_connection",
  "azurerm_virtual_network_peering",
}

environment := data.environment

deny[msg] {
  environment != "dev"

  change := input.resource_changes[_]
  change.change.actions[_] == "create"
  change.type in network_resource_types

  msg := sprintf(
    "DENY [network-outside-dev] %s: network resource type '%s' cannot be created in '%s'. Network infrastructure in staging/prod is managed centrally by the platform team.",
    [change.address, change.type, environment],
  )
}
