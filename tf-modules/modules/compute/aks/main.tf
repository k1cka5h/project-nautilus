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
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${local.name_prefix}-aks"
}

# ── AKS Cluster ────────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = local.name_prefix
  tags                = var.tags

  # System node pool — keeps platform add-ons separate from workload pods.
  default_node_pool {
    name           = "system"
    node_count     = var.system_node_count
    vm_size        = var.system_node_vm_size
    vnet_subnet_id = var.subnet_id
    # Taint the system pool so application pods do not schedule here.
    node_taints    = ["CriticalAddonsOnly=true:NoSchedule"]
    tags           = var.tags
  }

  # Managed identity — platform assigns RBAC externally via the outputs.
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI — required for VNet-native pod IPs.
  network_profile {
    network_plugin    = "azure"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    load_balancer_sku = "standard"
  }

  # Azure RBAC + AAD integration.
  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # OMS / Log Analytics monitoring.
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  lifecycle {
    # Kubernetes patch versions are updated via the upgrade pipeline, not here.
    ignore_changes = [kubernetes_version]
  }
}

# ── Additional Node Pools ──────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = var.additional_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.vm_size
  vnet_subnet_id        = var.subnet_id
  enable_auto_scaling   = each.value.enable_auto_scaling
  node_count            = each.value.enable_auto_scaling ? null : each.value.node_count
  min_count             = each.value.enable_auto_scaling ? each.value.min_count : null
  max_count             = each.value.enable_auto_scaling ? each.value.max_count : null
  node_labels           = each.value.labels
  node_taints           = each.value.taints
  tags                  = var.tags
}

# ── Delete protection (non-dev) ─────────────────────────────────────────────────

resource "azurerm_management_lock" "cluster" {
  count      = var.environment != "dev" ? 1 : 0
  name       = "${local.name_prefix}-aks-lock"
  scope      = azurerm_kubernetes_cluster.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Nautilus platform. Open a #platform-infra ticket to remove."
}
