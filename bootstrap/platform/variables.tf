variable "platform_subscription_id" {
  description = "Azure subscription ID where platform infrastructure (state backend, resource group) will be created."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group that will hold platform infrastructure."
  type        = string
  default     = "platform-rg"
}

variable "location" {
  description = "Azure region for platform infrastructure."
  type        = string
  default     = "eastus"
}

variable "state_storage_account_name" {
  description = "Name of the storage account used as the Terraform state backend. Must be globally unique, 3-24 lowercase alphanumeric characters."
  type        = string
  default     = "platformtfstate"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "github_org" {
  description = "GitHub organization slug (e.g. k1cka5h). Used to scope the platform SP's OIDC federated credential."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for the Nautilus platform repo (e.g. project-nautilus). Used to scope the platform SP's OIDC federated credential."
  type        = string
}
