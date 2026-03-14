package nautilus.deny_permission_changes_outside_dev

import future.keywords.in

# Permission resource types that may only be created or modified in dev.
# In staging and prod, all RBAC is managed by the platform team.
permission_resource_types := {
  "azurerm_role_assignment",
  "azurerm_role_definition",
  "azurerm_user_assigned_identity",
  "azurerm_federated_identity_credential",
}

environment := data.environment

deny[msg] {
  environment != "dev"

  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update", "delete"}
  change.type in permission_resource_types

  msg := sprintf(
    "DENY [permissions-outside-dev] %s: permission resource type '%s' cannot be managed in '%s'. All RBAC in staging/prod is owned by the platform team — open a #platform-infra ticket.",
    [change.address, change.type, environment],
  )
}
