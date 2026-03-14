terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Backend is configured per-environment at init time:
  #   terraform init -backend-config=../dev/backend.hcl
  # No backend block here — partial configuration is intentional.
  backend "azurerm" {}
}
