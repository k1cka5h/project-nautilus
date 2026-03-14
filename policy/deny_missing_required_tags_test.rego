package nautilus.deny_missing_required_tags_test

import future.keywords.in
import data.nautilus.deny_missing_required_tags

# ── resources with all required tags pass ─────────────────────────────────────

test_allow_resource_with_all_required_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server.db",
    "type":    "azurerm_postgresql_flexible_server",
    "change":  {
      "actions": ["create"],
      "after":   {"tags": {"managed_by": "terraform", "project": "myapp", "environment": "prod"}},
    },
  }]}
  count(msgs) == 0
}

test_allow_resource_with_extra_tags {
  # Extra tags beyond the required set are always fine
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_kubernetes_cluster.aks",
    "type":    "azurerm_kubernetes_cluster",
    "change":  {
      "actions": ["create"],
      "after":   {"tags": {
        "managed_by":  "terraform",
        "project":     "myapp",
        "environment": "dev",
        "team":        "platform",
        "cost_center": "engineering",
      }},
    },
  }]}
  count(msgs) == 0
}

# ── resources missing tags are denied ─────────────────────────────────────────

test_deny_resource_with_no_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server.db",
    "type":    "azurerm_postgresql_flexible_server",
    "change":  {"actions": ["create"], "after": {}},
  }]}
  count(msgs) == 1
}

test_deny_resource_with_empty_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_virtual_network.app",
    "type":    "azurerm_virtual_network",
    "change":  {"actions": ["create"], "after": {"tags": {}}},
  }]}
  count(msgs) == 1
}

test_deny_resource_missing_managed_by {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_virtual_network.app",
    "type":    "azurerm_virtual_network",
    "change":  {
      "actions": ["create"],
      "after":   {"tags": {"project": "myapp", "environment": "dev"}},
    },
  }]}
  count(msgs) == 1
}

test_deny_resource_missing_project {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_kubernetes_cluster.aks",
    "type":    "azurerm_kubernetes_cluster",
    "change":  {
      "actions": ["create"],
      "after":   {"tags": {"managed_by": "terraform", "environment": "prod"}},
    },
  }]}
  count(msgs) == 1
}

test_deny_resource_missing_environment {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_kubernetes_cluster.aks",
    "type":    "azurerm_kubernetes_cluster",
    "change":  {
      "actions": ["create"],
      "after":   {"tags": {"managed_by": "terraform", "project": "myapp"}},
    },
  }]}
  count(msgs) == 1
}

test_deny_missing_tags_on_update {
  # Updates also require the required tags
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server.db",
    "type":    "azurerm_postgresql_flexible_server",
    "change":  {"actions": ["update"], "after": {"tags": {"project": "myapp"}}},
  }]}
  count(msgs) == 1
}

# ── exempt resource types are never checked ───────────────────────────────────

test_allow_management_lock_without_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_management_lock.vnet",
    "type":    "azurerm_management_lock",
    "change":  {"actions": ["create"], "after": {"name": "vnet-lock"}},
  }]}
  count(msgs) == 0
}

test_allow_role_assignment_without_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_role_assignment.aks_acr",
    "type":    "azurerm_role_assignment",
    "change":  {"actions": ["create"], "after": {}},
  }]}
  count(msgs) == 0
}

test_allow_subnet_nsg_association_without_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_subnet_network_security_group_association.app",
    "type":    "azurerm_subnet_network_security_group_association",
    "change":  {"actions": ["create"], "after": {}},
  }]}
  count(msgs) == 0
}

test_allow_postgres_database_resource_without_tags {
  # Individual database resources inside a server don't support tags
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server_database.appdb",
    "type":    "azurerm_postgresql_flexible_server_database",
    "change":  {"actions": ["create"], "after": {"name": "appdb"}},
  }]}
  count(msgs) == 0
}

test_allow_node_pool_without_tags {
  # Node pools inherit tags from the cluster; the resource itself is exempt
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_kubernetes_cluster_node_pool.workers",
    "type":    "azurerm_kubernetes_cluster_node_pool",
    "change":  {"actions": ["create"], "after": {"name": "workers"}},
  }]}
  count(msgs) == 0
}

# ── delete actions are not checked for tags ───────────────────────────────────

test_allow_delete_without_tags {
  msgs := deny_missing_required_tags.deny with input as {"resource_changes": [{
    "address": "azurerm_virtual_network.app",
    "type":    "azurerm_virtual_network",
    "change":  {"actions": ["delete"], "after": null},
  }]}
  count(msgs) == 0
}
