terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ── Policy definitions ──────────────────────────────────────────────────────────
# Loaded from JSON files so diffs are easy to review.

resource "azurerm_policy_definition" "deny_public_resources" {
  name         = "nautilus-deny-public-resources"
  policy_type  = "Custom"
  mode         = "All"
  display_name = jsondecode(file("${path.module}/policies/deny_public_resources.json")).displayName
  description  = jsondecode(file("${path.module}/policies/deny_public_resources.json")).description

  policy_rule = jsonencode(
    jsondecode(file("${path.module}/policies/deny_public_resources.json")).policyRule
  )
}

resource "azurerm_policy_definition" "deny_network_write_nonprod" {
  name         = "nautilus-deny-network-write-nonprod"
  policy_type  = "Custom"
  mode         = "All"
  display_name = jsondecode(file("${path.module}/policies/deny_network_write_nonprod.json")).displayName
  description  = jsondecode(file("${path.module}/policies/deny_network_write_nonprod.json")).description

  policy_rule = jsonencode(
    jsondecode(file("${path.module}/policies/deny_network_write_nonprod.json")).policyRule
  )
}

resource "azurerm_policy_definition" "deny_role_assignments_nonprod" {
  name         = "nautilus-deny-role-assignments-nonprod"
  policy_type  = "Custom"
  mode         = "All"
  display_name = jsondecode(file("${path.module}/policies/deny_role_assignments_nonprod.json")).displayName
  description  = jsondecode(file("${path.module}/policies/deny_role_assignments_nonprod.json")).description

  policy_rule = jsonencode(
    jsondecode(file("${path.module}/policies/deny_role_assignments_nonprod.json")).policyRule
  )
}

# ── Policy assignments ──────────────────────────────────────────────────────────
# deny_public_resources applies everywhere (management group scope).

resource "azurerm_management_group_policy_assignment" "deny_public_resources" {
  name                 = "deny-public-resources"
  policy_definition_id = azurerm_policy_definition.deny_public_resources.id
  management_group_id  = var.management_group_id
  display_name         = "Deny public-facing resources (all environments)"
}

# deny_network_write and deny_role_assignments apply only to staging and prod.

resource "azurerm_subscription_policy_assignment" "deny_network_write_nonprod" {
  for_each = { for env, sub_id in var.subscription_ids : env => sub_id if env != "dev" }

  name                 = "deny-network-write-${each.key}"
  policy_definition_id = azurerm_policy_definition.deny_network_write_nonprod.id
  subscription_id      = "/subscriptions/${each.value}"
  display_name         = "Deny network writes — ${each.key}"
}

resource "azurerm_subscription_policy_assignment" "deny_role_assignments_nonprod" {
  for_each = { for env, sub_id in var.subscription_ids : env => sub_id if env != "dev" }

  name                 = "deny-role-assignments-${each.key}"
  policy_definition_id = azurerm_policy_definition.deny_role_assignments_nonprod.id
  subscription_id      = "/subscriptions/${each.value}"
  display_name         = "Deny RBAC changes — ${each.key}"
}

# ── Budget alerts ───────────────────────────────────────────────────────────────
# Alert at 80% and 100% of the monthly cap per environment.

resource "azurerm_consumption_budget_subscription" "this" {
  for_each = var.subscription_ids

  name            = "nautilus-${each.key}-budget"
  subscription_id = "/subscriptions/${each.value}"
  amount          = var.monthly_budget_amounts[each.key]
  time_grain      = "Monthly"

  time_period {
    start_date = "2026-01-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }

  notification {
    enabled        = true
    threshold      = 90
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_alert_emails
  }
}
