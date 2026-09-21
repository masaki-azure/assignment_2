output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "webapp_names" {
  value = { for k, v in azurerm_linux_web_app.apps : k => v.name }
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.pg.fqdn
}
