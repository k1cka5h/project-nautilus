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
  description = "Name of the Azure resource group to create."
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus, westeurope)."
  type        = string
  default     = "eastus"
}

variable "address_space" {
  description = "List of CIDR blocks for the virtual network."
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet name to subnet configuration."
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
  default = {}
}

variable "private_dns_zones" {
  description = "List of private DNS zone names to create and link to the VNet."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Azure resource tags. Required tags are injected by the construct library."
  type        = map(string)
  default     = {}
}
