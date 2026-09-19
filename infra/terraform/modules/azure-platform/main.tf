resource "random_id" "suffix" {
  byte_length = 3
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "platform" {
  name                = replace("acr${var.name_prefix}${random_id.suffix.hex}", "-", "")
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  sku                 = "Premium" # required for private endpoints / customer-managed keys / geo-replication
  admin_enabled       = false     # disable static admin credentials; use AAD/managed identity auth

  public_network_access_enabled = false

  tags = var.tags
}

resource "azurerm_storage_account" "platform" {
  name                = substr(replace("st${var.name_prefix}${random_id.suffix.hex}", "-", ""), 0, 24)
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location

  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"

  min_tls_version                  = "TLS1_2"
  enable_https_traffic_only        = true
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  shared_access_key_enabled        = false # force AAD/RBAC auth over the account instead of shared keys

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_name  = azurerm_storage_account.platform.name
  container_access_type = "private"
}

############################################
# On-prem Windows AD integration (documented, not provisioned)
#
# This repo has no on-prem Active Directory to integrate with, so no
# resources are declared here. In a real IDP environment, the intended
# pattern is:
#
#   1. Deploy Azure AD Connect (or Azure AD Connect cloud sync) on a
#      domain-joined Windows server in the on-prem network, syncing
#      on-prem AD users/groups into Azure AD (Entra ID) via a scheduled
#      delta sync (default every 30 minutes).
#   2. Enable Password Hash Sync or pass-through auth, plus seamless SSO,
#      so on-prem Windows AD credentials authenticate against Azure AD
#      without a second credential store.
#   3. Grant developer/CI groups synced from AD RBAC roles on this
#      resource group (e.g. "AcrPush" on the ACR, "Storage Blob Data
#      Contributor" scoped to the artifacts container) instead of
#      per-user role assignments, so on-prem group membership changes
#      propagate automatically to cloud access.
#   4. Terraform module stub for that RBAC wiring would live here as
#      azurerm_role_assignment resources keyed off an
#      azuread_group data source once a real AD/Azure AD Connect
#      tenant exists to look groups up against.
############################################
