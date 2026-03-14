package nautilus.deny_deletions_outside_dev_test

import future.keywords.in
import data.nautilus.deny_deletions_outside_dev

# ── delete outside dev is blocked ────────────────────────────────────────────

test_deny_delete_postgres_in_staging {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["delete"], "after": null},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_delete_aks_in_prod {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["delete"], "after": null},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_replace_postgres_in_prod {
  # Replace = ["delete", "create"]. Both orderings must be blocked.
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["delete", "create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_replace_create_delete_ordering_in_prod {
  # Terraform sometimes uses ["create", "delete"] for create-before-destroy
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create", "delete"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_delete_vnet_in_staging {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_virtual_network.app",
      "type":    "azurerm_virtual_network",
      "change":  {"actions": ["delete"], "after": null},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

# ── deletes are allowed in dev ────────────────────────────────────────────────

test_allow_delete_in_dev {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["delete"], "after": null},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

test_allow_replace_in_dev {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["delete", "create"], "after": {}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

# ── create-only and update-only are allowed outside dev ──────────────────────

test_allow_create_outside_dev {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}

test_allow_update_outside_dev {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["update"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 0
}

test_allow_no_op_outside_dev {
  msgs := deny_deletions_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["no-op"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}
