package nautilus.deny_public_resources

import future.keywords.in

# Public resource types that are never permitted in any environment.
public_resource_types := {
  "azurerm_public_ip",
  "azurerm_public_ip_prefix",
}

# Resource attribute paths that indicate public network access is enabled.
# Checked on create and update actions.
deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  change.type in public_resource_types

  msg := sprintf(
    "DENY [public-resources] %s: public IP resources are not permitted. Use private endpoints instead.",
    [change.address],
  )
}

deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  after := change.change.after

  # Any resource that exposes public_network_access_enabled = true.
  after.public_network_access_enabled == true

  msg := sprintf(
    "DENY [public-resources] %s: public_network_access_enabled must be false. All resources must be private.",
    [change.address],
  )
}

deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  after := change.change.after

  # Azure Storage accounts must not allow public blob access.
  change.type == "azurerm_storage_account"
  after.allow_blob_public_access == true

  msg := sprintf(
    "DENY [public-resources] %s: allow_blob_public_access must be false.",
    [change.address],
  )
}
