package nautilus.deny_public_resources_test

import future.keywords.in
import data.nautilus.deny_public_resources

# ── public IP resources ────────────────────────────────────────────────────────

test_deny_public_ip_create {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_public_ip.egress",
    "type":    "azurerm_public_ip",
    "change":  {"actions": ["create"], "after": {}},
  }]}
  count(msgs) == 1
}

test_deny_public_ip_update {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_public_ip.egress",
    "type":    "azurerm_public_ip",
    "change":  {"actions": ["update"], "after": {}},
  }]}
  count(msgs) == 1
}

test_deny_public_ip_prefix_create {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_public_ip_prefix.test",
    "type":    "azurerm_public_ip_prefix",
    "change":  {"actions": ["create"], "after": {}},
  }]}
  count(msgs) == 1
}

test_allow_public_ip_delete {
  # Deletion of a public IP (removing one that exists) should not be blocked by
  # this policy — deny_deletions_outside_dev.rego handles deletion enforcement.
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_public_ip.egress",
    "type":    "azurerm_public_ip",
    "change":  {"actions": ["delete"], "after": null},
  }]}
  count(msgs) == 0
}

# ── public_network_access_enabled ─────────────────────────────────────────────

test_deny_public_network_access_enabled_on_create {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server.db",
    "type":    "azurerm_postgresql_flexible_server",
    "change":  {"actions": ["create"], "after": {"public_network_access_enabled": true}},
  }]}
  count(msgs) == 1
}

test_deny_public_network_access_enabled_on_update {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_key_vault.kv",
    "type":    "azurerm_key_vault",
    "change":  {"actions": ["update"], "after": {"public_network_access_enabled": true}},
  }]}
  count(msgs) == 1
}

test_allow_private_network_access {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_postgresql_flexible_server.db",
    "type":    "azurerm_postgresql_flexible_server",
    "change":  {"actions": ["create"], "after": {"public_network_access_enabled": false}},
  }]}
  count(msgs) == 0
}

# ── storage blob public access ────────────────────────────────────────────────

test_deny_blob_public_access_enabled {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_storage_account.assets",
    "type":    "azurerm_storage_account",
    "change":  {"actions": ["create"], "after": {"allow_blob_public_access": true}},
  }]}
  count(msgs) == 1
}

test_allow_private_blob_storage {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_storage_account.assets",
    "type":    "azurerm_storage_account",
    "change":  {"actions": ["create"], "after": {"allow_blob_public_access": false}},
  }]}
  count(msgs) == 0
}

# ── unrelated resources pass through ─────────────────────────────────────────

test_allow_resource_group {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_resource_group.app",
    "type":    "azurerm_resource_group",
    "change":  {"actions": ["create"], "after": {"name": "myapp-rg"}},
  }]}
  count(msgs) == 0
}

test_allow_aks_cluster {
  msgs := deny_public_resources.deny with input as {"resource_changes": [{
    "address": "azurerm_kubernetes_cluster.aks",
    "type":    "azurerm_kubernetes_cluster",
    "change":  {"actions": ["create"], "after": {"name": "myapp-aks"}},
  }]}
  count(msgs) == 0
}
