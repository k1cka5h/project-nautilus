output "server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "server_name" {
  description = "Name of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "Fully qualified domain name for the server. Use as the connection host."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "administrator_login" {
  description = "Admin username (use to construct the connection string)."
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}

output "database_ids" {
  description = "Map of database name to resource ID."
  value       = { for k, v in azurerm_postgresql_flexible_server_database.this : k => v.id }
}
