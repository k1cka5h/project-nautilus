variable "subscription_ids" {
  description = "Map of environment name to subscription ID. Used to scope policy assignments."
  type        = map(string)
  # Example: { dev = "00000000-...", staging = "11111111-...", prod = "22222222-..." }
}

variable "management_group_id" {
  description = "Management group ID for policies that apply to all environments (e.g. deny public resources)."
  type        = string
}

variable "monthly_budget_amounts" {
  description = "Monthly budget cap (USD) per environment. Pipeline blocks applies that would exceed the SKU allowlist for that tier."
  type        = map(number)
  default = {
    dev     = 500
    staging = 2000
    prod    = 10000
  }
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget threshold alerts."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all governance resources."
  type        = map(string)
  default     = {}
}
