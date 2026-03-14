output "state_storage_account_id" {
  description = "Resource ID of the Terraform state storage account. Pass this to bootstrap/product-team as var.state_storage_account_id."
  value       = azurerm_storage_account.tfstate.id
}

output "state_storage_account_name" {
  description = "Name of the Terraform state storage account."
  value       = azurerm_storage_account.tfstate.name
}

output "state_container_name" {
  description = "Name of the blob container holding all state files."
  value       = azurerm_storage_container.tfstate.name
}

output "platform_client_id" {
  description = "Client ID of the platform service principal. Set as ARM_CLIENT_ID in the Nautilus repo's GitHub Actions secrets."
  value       = azuread_application.platform.client_id
}

output "platform_subscription_id" {
  description = "Subscription ID where the platform SP has Contributor access."
  value       = var.platform_subscription_id
}

output "tenant_id" {
  description = "Azure AD tenant ID. Set as AZURE_TENANT_ID in the Nautilus repo's GitHub Actions variables."
  value       = azuread_service_principal.platform.application_tenant_id
}

output "next_steps" {
  description = "Summary of manual steps to complete after applying this module."
  value       = <<-EOT
    Bootstrap complete. Next steps:

    1. Set these GitHub Actions secrets on the Nautilus repo (${var.github_org}/${var.github_repo}):
         ARM_CLIENT_ID       = ${azuread_application.platform.client_id}
         ARM_SUBSCRIPTION_ID = ${var.platform_subscription_id}

    2. Set this GitHub Actions variable on the Nautilus repo:
         AZURE_TENANT_ID = ${azuread_service_principal.platform.application_tenant_id}

    3. Run bootstrap/product-team for each product team, passing:
         state_storage_account_id = "${azurerm_storage_account.tfstate.id}"

    4. Optionally migrate this module's local state to the remote backend:
         Edit backend.tf to add an azurerm backend block, then:
         terraform init -migrate-state
  EOT
}
