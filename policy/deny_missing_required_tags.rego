package nautilus.deny_missing_required_tags

import future.keywords.in

# Every Azure resource provisioned through a developer stack must carry these
# three tags. They are injected automatically by the construct libraries via
# RequiredTags() — this policy is a backstop that catches anything that slips
# through (e.g. a developer calling TerraformResource directly, or a future
# construct that forgets to call the tagging helper).

required_tag_keys := {"managed_by", "project", "environment"}

# Resource types that don't support tags or where tags are not meaningful.
# These are infrastructure/governance resources managed by the platform team.
exempt_types := {
  "azurerm_management_lock",
  "azurerm_policy_assignment",
  "azurerm_management_group_policy_assignment",
  "azurerm_subscription_policy_assignment",
  "azurerm_resource_policy_assignment",
  "azurerm_consumption_budget_subscription",
  "azurerm_consumption_budget_resource_group",
  "azurerm_role_assignment",
  "azurerm_role_definition",
  "azurerm_federated_identity_credential",
  "azurerm_subnet_network_security_group_association",
  "azurerm_subnet_route_table_association",
  "azurerm_private_dns_zone_virtual_network_link",
  "azurerm_postgresql_flexible_server_database",
  "azurerm_postgresql_flexible_server_configuration",
  "azurerm_kubernetes_cluster_node_pool",
}

deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  not change.type in exempt_types

  after := change.change.after
  tags  := object.get(after, "tags", {})

  missing := {k | k := required_tag_keys[_]; not tags[k]}
  count(missing) > 0

  msg := sprintf(
    "DENY [required-tags] %s: missing required tags %v. All resources must include 'managed_by', 'project', and 'environment'. Use the construct library — it injects these automatically.",
    [change.address, missing],
  )
}
