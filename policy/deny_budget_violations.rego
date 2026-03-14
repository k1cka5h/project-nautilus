package nautilus.deny_budget_violations

import future.keywords.in

# Allowed VM SKUs per environment tier.
# dev: small SKUs only. staging: mid-tier. prod: any approved SKU.
# Developers cannot use SKUs outside their environment's allowlist — this
# acts as a quota guardrail before Azure Budget alerts would fire.

allowed_vm_skus := {
  "dev": {
    "Standard_B2s", "Standard_B4ms",
    "Standard_D2s_v3", "Standard_D4s_v3",
  },
  "staging": {
    "Standard_B2s", "Standard_B4ms",
    "Standard_D2s_v3", "Standard_D4s_v3",
    "Standard_D8s_v3", "Standard_D16s_v3",
    "Standard_E4s_v3", "Standard_E8s_v3",
  },
  "prod": {
    "Standard_D4s_v3",  "Standard_D8s_v3",
    "Standard_D16s_v3", "Standard_D32s_v3",
    "Standard_E4s_v3",  "Standard_E8s_v3",
    "Standard_E16s_v3", "Standard_E32s_v3",
    "Standard_F8s_v2",  "Standard_F16s_v2",
  },
}

# Allowed PostgreSQL SKUs per environment tier.
allowed_postgres_skus := {
  "dev": {
    "B_Standard_B1ms", "B_Standard_B2ms",
    "GP_Standard_D2s_v3",
  },
  "staging": {
    "GP_Standard_D2s_v3", "GP_Standard_D4s_v3",
    "GP_Standard_D8s_v3",
  },
  "prod": {
    "GP_Standard_D4s_v3",  "GP_Standard_D8s_v3",
    "GP_Standard_D16s_v3", "GP_Standard_D32s_v3",
    "MO_Standard_E4ds_v4", "MO_Standard_E8ds_v4",
  },
}

environment := data.environment

# AKS node pool VM size check.
deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  change.type in {"azurerm_kubernetes_cluster", "azurerm_kubernetes_cluster_node_pool"}

  vm_size := change.change.after.vm_size
  not vm_size in allowed_vm_skus[environment]

  msg := sprintf(
    "DENY [budget] %s: VM SKU '%s' is not on the approved list for '%s'. Allowed: %v",
    [change.address, vm_size, environment, allowed_vm_skus[environment]],
  )
}

# PostgreSQL SKU check.
deny[msg] {
  change := input.resource_changes[_]
  change.change.actions[_] in {"create", "update"}
  change.type == "azurerm_postgresql_flexible_server"

  sku := change.change.after.sku_name
  not sku in allowed_postgres_skus[environment]

  msg := sprintf(
    "DENY [budget] %s: PostgreSQL SKU '%s' is not on the approved list for '%s'. Allowed: %v",
    [change.address, sku, environment, allowed_postgres_skus[environment]],
  )
}
