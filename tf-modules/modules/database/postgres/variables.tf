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

variable "delegated_subnet_id" {
  description = "Resource ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Resource ID of the privatelink.postgres.database.azure.com private DNS zone."
  type        = string
}

variable "administrator_password" {
  description = "Server admin password. Must meet Azure complexity requirements."
  type        = string
  sensitive   = true
}

variable "databases" {
  description = "List of database names to create on the server."
  type        = list(string)
  default     = []
}

variable "sku_name" {
  description = "Compute SKU for the flexible server. Use B_Standard_B1ms for dev only."
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "storage_mb" {
  description = "Storage size in MB. Min 32768."
  type        = number
  default     = 32768
  validation {
    condition     = var.storage_mb >= 32768
    error_message = "storage_mb must be at least 32768 (32 GiB)."
  }
}

variable "pg_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "15"
  validation {
    condition     = contains(["14", "15", "16"], var.pg_version)
    error_message = "pg_version must be 14, 15, or 16."
  }
}

variable "high_availability_mode" {
  description = "HA mode: Disabled or ZoneRedundant. Required ZoneRedundant in prod."
  type        = string
  default     = "Disabled"
  validation {
    condition     = contains(["Disabled", "ZoneRedundant"], var.high_availability_mode)
    error_message = "high_availability_mode must be Disabled or ZoneRedundant."
  }
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backups. Increases cost."
  type        = bool
  default     = false
}

variable "server_configurations" {
  description = "Map of PostgreSQL server parameter name to value."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Azure resource tags."
  type        = map(string)
  default     = {}
}
