output "client_ids" {
  description = "Map of environment to service principal client ID. Each value is set as <ENV>_AZURE_CLIENT_ID in the product repo's GitHub Actions secrets."
  value       = { for env, app in azuread_application.this : env => app.client_id }
}

output "subscription_ids" {
  description = "Map of environment to Azure subscription ID. Each value is set as <ENV>_AZURE_SUBSCRIPTION_ID in the product repo's GitHub Actions secrets."
  value       = var.subscription_ids
}

output "tenant_id" {
  description = "Azure AD tenant ID. Set as AZURE_TENANT_ID in the product repo's GitHub Actions variables (shared across environments)."
  value       = azuread_service_principal.this["dev"].application_tenant_id
}

output "github_secrets" {
  description = "Ready-to-copy summary of GitHub Actions secrets to set on the product team's repo."
  value       = <<-EOT
    Set these GitHub Actions secrets on ${var.github_org}/${var.github_repo}:

      DEV_AZURE_CLIENT_ID        = ${azuread_application.this["dev"].client_id}
      DEV_AZURE_SUBSCRIPTION_ID  = ${var.subscription_ids["dev"]}

      QA_AZURE_CLIENT_ID         = ${azuread_application.this["qa"].client_id}
      QA_AZURE_SUBSCRIPTION_ID   = ${var.subscription_ids["qa"]}

      STAGE_AZURE_CLIENT_ID      = ${azuread_application.this["stage"].client_id}
      STAGE_AZURE_SUBSCRIPTION_ID = ${var.subscription_ids["stage"]}

      PROD_AZURE_CLIENT_ID       = ${azuread_application.this["prod"].client_id}
      PROD_AZURE_SUBSCRIPTION_ID = ${var.subscription_ids["prod"]}

    Set this GitHub Actions variable (not secret) on ${var.github_org}/${var.github_repo}:

      AZURE_TENANT_ID = ${azuread_service_principal.this["dev"].application_tenant_id}

    Then set these secrets manually (not managed by Terraform):
      TF_MODULES_DEPLOY_KEY   — private half of the SSH deploy key
      DB_ADMIN_PASSWORD       — PostgreSQL admin password
      LOG_WORKSPACE_ID        — Log Analytics workspace resource ID
  EOT
}
