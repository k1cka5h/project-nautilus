variable "project" {
  description = "Short project name. Used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, qa, stage, staging, or prod."
  type        = string
  validation {
    condition     = contains(["dev", "qa", "stage", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, stage, staging, prod."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region. Must match the resource group's location."
  type        = string
  default     = "eastus"
}

variable "subnet_id" {
  description = "Subnet resource ID for the system and default node pool VMs."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for cluster diagnostics."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Must be on the platform-approved list."
  type        = string
  default     = "1.29"
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_count" {
  description = "Number of nodes in the system pool. Use 3 in prod for zone redundancy."
  type        = number
  default     = 3
  validation {
    condition     = var.system_node_count >= 1
    error_message = "system_node_count must be at least 1."
  }
}

variable "additional_node_pools" {
  description = "Map of node pool name (max 12 chars) to pool configuration."
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

variable "admin_group_object_ids" {
  description = "AAD group object IDs to grant cluster-admin role."
  type        = list(string)
  default     = []
}

variable "service_cidr" {
  description = "CIDR for Kubernetes service IPs. Must not overlap with the VNet."
  type        = string
  default     = "10.240.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within service_cidr assigned to kube-dns."
  type        = string
  default     = "10.240.0.10"
}

variable "tags" {
  description = "Azure resource tags."
  type        = map(string)
  default     = {}
}
