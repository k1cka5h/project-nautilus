package nautilus.deny_budget_violations_test

import future.keywords.in
import data.nautilus.deny_budget_violations

# ── VM SKU enforcement ────────────────────────────────────────────────────────

test_deny_prod_sku_in_dev {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_D32s_v3"}},
    }]}
    with data.environment as "dev"
  count(msgs) == 1
}

test_deny_unapproved_vm_sku_in_staging {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_M64s"}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_allow_approved_vm_sku_in_dev {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_D2s_v3"}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

test_allow_approved_vm_sku_in_staging {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_D8s_v3"}},
    }]}
    with data.environment as "staging"
  count(msgs) == 0
}

test_allow_approved_vm_sku_in_prod {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_D16s_v3"}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}

test_deny_small_vm_sku_in_prod {
  # B-series SKUs are only for dev — they're not reliable enough for prod
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_B2s"}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_vm_sku_on_node_pool {
  # The policy applies to both cluster and node pool resources
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster_node_pool.workers",
      "type":    "azurerm_kubernetes_cluster_node_pool",
      "change":  {"actions": ["create"], "after": {"vm_size": "Standard_M64s"}},
    }]}
    with data.environment as "dev"
  count(msgs) == 1
}

# ── PostgreSQL SKU enforcement ─────────────────────────────────────────────────

test_deny_prod_postgres_sku_in_dev {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {"sku_name": "GP_Standard_D16s_v3"}},
    }]}
    with data.environment as "dev"
  count(msgs) == 1
}

test_allow_approved_postgres_sku_in_dev {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {"sku_name": "B_Standard_B2ms"}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

test_allow_approved_postgres_sku_in_staging {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {"sku_name": "GP_Standard_D4s_v3"}},
    }]}
    with data.environment as "staging"
  count(msgs) == 0
}

test_deny_dev_postgres_sku_in_prod {
  # Burstable SKUs are not permitted in prod
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {"sku_name": "B_Standard_B1ms"}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_allow_approved_postgres_sku_in_prod {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {"sku_name": "GP_Standard_D8s_v3"}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}

# ── non-compute resources are not affected ────────────────────────────────────

test_allow_resource_group_always {
  msgs := deny_budget_violations.deny
    with input as {"resource_changes": [{
      "address": "azurerm_resource_group.app",
      "type":    "azurerm_resource_group",
      "change":  {"actions": ["create"], "after": {"name": "myapp-prod-rg"}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}
