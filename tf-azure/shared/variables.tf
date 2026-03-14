# ── Identity ───────────────────────────────────────────────────────────────────

variable "project" {
  description = "Short project name used in resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment. Controls naming, sizing, and HA defaults."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "stage", "prod"], var.environment)
    error_message = "environment must be dev, qa, stage, or prod."
  }
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus"
}

# ── Resource Groups ─────────────────────────────────────────────────────────────

variable "network_resource_group" {
  description = "Resource group for networking resources."
  type        = string
}

variable "app_resource_group" {
  description = "Resource group for application resources (AKS, database)."
  type        = string
}

# ── Networking ──────────────────────────────────────────────────────────────────

variable "address_space" {
  description = "CIDR block(s) for the virtual network."
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet name to configuration."
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      name    = string
      service = string
      actions = list(string)
    }), null)
    nsg_rules = optional(list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    })), [])
  }))
}

variable "private_dns_zones" {
  description = "Private DNS zone names to create and link to the VNet."
  type        = list(string)
  default     = ["privatelink.postgres.database.azure.com"]
}

# ── Database ────────────────────────────────────────────────────────────────────

variable "enable_database" {
  description = "Whether to provision a PostgreSQL Flexible Server."
  type        = bool
  default     = true
}

variable "postgres_sku" {
  description = "PostgreSQL compute SKU. Must be on the platform-approved list for this environment."
  type        = string
}

variable "postgres_storage_mb" {
  description = "Allocated storage in MB."
  type        = number
  default     = 32768
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "15"
}

variable "postgres_ha_mode" {
  description = "High-availability mode: Disabled or ZoneRedundant."
  type        = string
  default     = "Disabled"
}

variable "postgres_geo_redundant_backup" {
  description = "Enable geo-redundant backups."
  type        = bool
  default     = false
}

variable "postgres_databases" {
  description = "Database names to create on the server."
  type        = list(string)
  default     = ["portal"]
}

variable "postgres_server_configurations" {
  description = "PostgreSQL server parameter overrides."
  type        = map(string)
  default     = {}
}

variable "administrator_password" {
  description = "PostgreSQL admin password. Supplied via TF_VAR_administrator_password — never stored in tfvars."
  type        = string
  sensitive   = true
}

# ── AKS ────────────────────────────────────────────────────────────────────────

variable "enable_aks" {
  description = "Whether to provision an AKS cluster."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version. Must be on the platform-approved list."
  type        = string
  default     = "1.29"
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
}

variable "system_node_count" {
  description = "Node count for the system pool. Use 3 in prod for zone redundancy."
  type        = number
  default     = 3
}

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes service IPs. Must not overlap with the VNet."
  type        = string
  default     = "192.168.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP within aks_service_cidr assigned to kube-dns."
  type        = string
  default     = "192.168.0.10"
}

variable "aks_admin_group_object_ids" {
  description = "AAD group object IDs to grant cluster-admin."
  type        = list(string)
  default     = []
}

variable "additional_node_pools" {
  description = "Additional AKS node pools keyed by pool name (max 12 chars)."
  type = map(object({
    vm_size             = optional(string, "Standard_D4s_v3")
    node_count          = optional(number, 2)
    enable_auto_scaling = optional(bool, false)
    min_count           = optional(number, 1)
    max_count           = optional(number, 10)
    labels              = optional(map(string), {})
    taints              = optional(list(string), [])
  }))
  default = {}
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the shared Log Analytics workspace for AKS diagnostics."
  type        = string
}

# ── Tagging ─────────────────────────────────────────────────────────────────────

variable "extra_tags" {
  description = "Additional tags merged onto all resources. Required tags (managed_by, project, environment) always win."
  type        = map(string)
  default     = {}
}
