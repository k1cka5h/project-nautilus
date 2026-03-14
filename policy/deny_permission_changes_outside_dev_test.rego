package nautilus.deny_permission_changes_outside_dev_test

import future.keywords.in
import data.nautilus.deny_permission_changes_outside_dev

# ── blocked create/update/delete outside dev ──────────────────────────────────

test_deny_role_assignment_create_in_staging {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_assignment.aks_acr",
      "type":    "azurerm_role_assignment",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_role_assignment_create_in_prod {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_assignment.aks_acr",
      "type":    "azurerm_role_assignment",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_role_assignment_update_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_assignment.aks_acr",
      "type":    "azurerm_role_assignment",
      "change":  {"actions": ["update"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_role_assignment_delete_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_assignment.aks_acr",
      "type":    "azurerm_role_assignment",
      "change":  {"actions": ["delete"], "after": null},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_role_definition_create_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_definition.custom",
      "type":    "azurerm_role_definition",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_managed_identity_create_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_user_assigned_identity.app",
      "type":    "azurerm_user_assigned_identity",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_federated_credential_create_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_federated_identity_credential.gh_actions",
      "type":    "azurerm_federated_identity_credential",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

# ── allowed in dev ────────────────────────────────────────────────────────────

test_allow_role_assignment_in_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_role_assignment.aks_acr",
      "type":    "azurerm_role_assignment",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

test_allow_managed_identity_in_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_user_assigned_identity.app",
      "type":    "azurerm_user_assigned_identity",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

# ── non-permission resources are unaffected ───────────────────────────────────

test_allow_postgres_server_outside_dev {
  msgs := deny_permission_changes_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}
