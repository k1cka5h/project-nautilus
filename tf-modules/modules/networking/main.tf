terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── Resource Group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Virtual Network ────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "this" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = var.tags
}

# ── Subnets ────────────────────────────────────────────────────────────────────

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation != null ? [each.value.delegation] : []
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

# ── Network Security Groups ────────────────────────────────────────────────────
# One NSG per subnet. Custom rules are applied on top of the platform defaults.

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "${local.name_prefix}-${each.key}-nsg"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ── Private DNS Zones ──────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.private_dns_zones)

  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = toset(var.private_dns_zones)

  name                  = "${local.name_prefix}-${replace(each.key, ".", "-")}-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

# ── Delete protection (non-dev) ─────────────────────────────────────────────────
# Management locks prevent accidental destruction of network infrastructure in
# staging and prod. To remove a resource in those environments, the platform team
# must manually delete the lock first — creating a deliberate break-glass step.

resource "azurerm_management_lock" "resource_group" {
  count      = var.environment != "dev" ? 1 : 0
  name       = "${local.name_prefix}-rg-lock"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Nautilus platform. Open a #platform-infra ticket to remove."
}

resource "azurerm_management_lock" "vnet" {
  count      = var.environment != "dev" ? 1 : 0
  name       = "${local.name_prefix}-vnet-lock"
  scope      = azurerm_virtual_network.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Nautilus platform. Open a #platform-infra ticket to remove."
}
