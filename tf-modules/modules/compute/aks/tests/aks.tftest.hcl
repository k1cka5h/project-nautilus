# Terraform module tests — compute/aks
# =====================================
# Uses terraform test (>= 1.7) with mock_provider so no Azure credentials
# are needed. Run with:
#   terraform test
# from the modules/compute/aks/ directory.

mock_provider "azurerm" {}

# ── shared variables ───────────────────────────────────────────────────────────

variables {
  project                    = "test"
  environment                = "dev"
  resource_group_name        = "test-dev-app-rg"
  location                   = "eastus"
  subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-dev-rg/providers/Microsoft.Network/virtualNetworks/test-dev-vnet/subnets/aks"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-rg/providers/Microsoft.OperationalInsights/workspaces/platform-logs"
  system_node_count          = 1
  system_node_vm_size        = "Standard_D2s_v3"
  kubernetes_version         = "1.29"
  service_cidr               = "10.240.0.0/16"
  dns_service_ip             = "10.240.0.10"
  admin_group_object_ids     = []
  additional_node_pools      = {}
  tags = {
    managed_by  = "terraform"
    project     = "test"
    environment = "dev"
  }
}

# ── naming convention ──────────────────────────────────────────────────────────

run "cluster_name_follows_convention" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.name == "test-dev-aks"
    error_message = "Cluster name must follow {project}-{environment}-aks"
  }
}

run "dns_prefix_follows_convention" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.dns_prefix == "test-dev"
    error_message = "DNS prefix must be {project}-{environment}"
  }
}

# ── system node pool ───────────────────────────────────────────────────────────

run "system_node_pool_is_tainted" {
  assert {
    condition     = contains(azurerm_kubernetes_cluster.this.default_node_pool[0].node_taints, "CriticalAddonsOnly=true:NoSchedule")
    error_message = "System node pool must be tainted CriticalAddonsOnly=true:NoSchedule to prevent workload pods scheduling here"
  }
}

run "system_node_pool_uses_specified_vm_size" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size == "Standard_D2s_v3"
    error_message = "System node pool VM size must match system_node_vm_size variable"
  }
}

# ── network profile ────────────────────────────────────────────────────────────

run "network_plugin_is_azure_cni" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure"
    error_message = "Network plugin must be 'azure' (Azure CNI) for VNet-native pod IPs"
  }
}

run "load_balancer_sku_is_standard" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].load_balancer_sku == "standard"
    error_message = "Load balancer SKU must be 'standard'"
  }
}

# ── identity ───────────────────────────────────────────────────────────────────

run "identity_is_system_assigned" {
  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "SystemAssigned"
    error_message = "Cluster identity must be SystemAssigned"
  }
}

# ── additional node pools ──────────────────────────────────────────────────────

run "no_additional_node_pools_by_default" {
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this) == 0
    error_message = "No additional node pools should be created by default"
  }
}

run "creates_additional_node_pool" {
  variables {
    additional_node_pools = {
      workers = {
        vm_size             = "Standard_D4s_v3"
        node_count          = 2
        enable_auto_scaling = false
        min_count           = null
        max_count           = null
        labels              = {}
        taints              = []
      }
    }
  }
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this) == 1
    error_message = "Expected 1 additional node pool"
  }
}

run "autoscaling_node_pool_sets_min_max" {
  variables {
    additional_node_pools = {
      workers = {
        vm_size             = "Standard_D4s_v3"
        node_count          = 3
        enable_auto_scaling = true
        min_count           = 2
        max_count           = 10
        labels              = {}
        taints              = []
      }
    }
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["workers"].enable_auto_scaling == true
    error_message = "Auto-scaling must be enabled on the worker pool"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["workers"].min_count == 2
    error_message = "min_count must be set when auto-scaling is enabled"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["workers"].max_count == 10
    error_message = "max_count must be set when auto-scaling is enabled"
  }
}

# ── management locks ──────────────────────────────────────────────────────────

run "no_management_lock_in_dev" {
  assert {
    condition     = length(azurerm_management_lock.cluster) == 0
    error_message = "No management lock should be created in dev"
  }
}

run "management_lock_created_in_staging" {
  variables {
    environment = "staging"
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "staging"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.cluster) == 1
    error_message = "Management lock must be created in staging"
  }
  assert {
    condition     = azurerm_management_lock.cluster[0].lock_level == "CanNotDelete"
    error_message = "Lock level must be CanNotDelete"
  }
}

run "management_lock_created_in_prod" {
  variables {
    environment       = "prod"
    system_node_count = 3
    tags = {
      managed_by  = "terraform"
      project     = "test"
      environment = "prod"
    }
  }
  assert {
    condition     = length(azurerm_management_lock.cluster) == 1
    error_message = "Management lock must be created in prod"
  }
}
