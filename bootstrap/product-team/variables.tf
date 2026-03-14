variable "product_name" {
  description = "Short product identifier used to name service principals (e.g. portal, myapp). Lowercase, no spaces."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.product_name))
    error_message = "product_name must be 2-21 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "github_org" {
  description = "GitHub organization slug (e.g. myorg)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for this product team's infrastructure repo (e.g. portal-infra)."
  type        = string
}

variable "subscription_ids" {
  description = <<-EOT
    Map of environment name to Azure subscription ID.
    The environment names must be exactly: dev, qa, stage, prod.
    Multiple environments may share a subscription — provide the same ID for each.

    Example (separate subscriptions per environment):
      {
        dev   = "00000000-0000-0000-0000-000000000001"
        qa    = "00000000-0000-0000-0000-000000000002"
        stage = "00000000-0000-0000-0000-000000000003"
        prod  = "00000000-0000-0000-0000-000000000004"
      }

    Example (shared subscription for non-prod):
      {
        dev   = "00000000-0000-0000-0000-000000000001"
        qa    = "00000000-0000-0000-0000-000000000001"
        stage = "00000000-0000-0000-0000-000000000001"
        prod  = "00000000-0000-0000-0000-000000000002"
      }
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for k in keys(var.subscription_ids) : contains(["dev", "qa", "stage", "prod"], k)])
    error_message = "subscription_ids keys must be exactly: dev, qa, stage, prod."
  }

  validation {
    condition     = length(keys(var.subscription_ids)) == 4
    error_message = "subscription_ids must have exactly four keys: dev, qa, stage, prod."
  }
}

variable "state_storage_account_id" {
  description = "Resource ID of the platform Terraform state storage account. From bootstrap/platform output: state_storage_account_id."
  type        = string
}

variable "platform_subscription_id" {
  description = "Azure subscription ID where the platform infrastructure lives. Used by the azurerm provider for authentication context."
  type        = string
}
