output "resource_group_name" {
  description = "Name of the Azure resource group holding the platform resources."
  value       = azurerm_resource_group.platform.name
}

output "acr_login_server" {
  description = "Login server for the Azure Container Registry."
  value       = azurerm_container_registry.platform.login_server
}

output "storage_account_name" {
  description = "Name of the private, encrypted storage account."
  value       = azurerm_storage_account.platform.name
}
