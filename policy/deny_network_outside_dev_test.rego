package nautilus.deny_network_outside_dev_test

import future.keywords.in
import data.nautilus.deny_network_outside_dev

# ── blocked in non-dev ────────────────────────────────────────────────────────

test_deny_vnet_create_in_staging {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_virtual_network.app",
      "type":    "azurerm_virtual_network",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_vnet_create_in_prod {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_virtual_network.app",
      "type":    "azurerm_virtual_network",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_subnet_create_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_subnet.app",
      "type":    "azurerm_subnet",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_nsg_create_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_network_security_group.app",
      "type":    "azurerm_network_security_group",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

test_deny_private_endpoint_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_private_endpoint.db",
      "type":    "azurerm_private_endpoint",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 1
}

test_deny_private_dns_zone_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_private_dns_zone.postgres",
      "type":    "azurerm_private_dns_zone",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 1
}

# ── allowed in dev ────────────────────────────────────────────────────────────

test_allow_vnet_create_in_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_virtual_network.app",
      "type":    "azurerm_virtual_network",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

test_allow_subnet_create_in_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_subnet.app",
      "type":    "azurerm_subnet",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "dev"
  count(msgs) == 0
}

# ── policy only blocks CREATE, not UPDATE ─────────────────────────────────────
# Platform-managed resources in staging/prod can still be updated through the
# privileged pipeline. Only net-new network resources are blocked.

test_allow_update_network_resource_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_virtual_network.app",
      "type":    "azurerm_virtual_network",
      "change":  {"actions": ["update"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 0
}

# ── non-network resources are unaffected ─────────────────────────────────────

test_allow_postgres_server_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_postgresql_flexible_server.db",
      "type":    "azurerm_postgresql_flexible_server",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "staging"
  count(msgs) == 0
}

test_allow_aks_cluster_outside_dev {
  msgs := deny_network_outside_dev.deny
    with input as {"resource_changes": [{
      "address": "azurerm_kubernetes_cluster.aks",
      "type":    "azurerm_kubernetes_cluster",
      "change":  {"actions": ["create"], "after": {}},
    }]}
    with data.environment as "prod"
  count(msgs) == 0
}
