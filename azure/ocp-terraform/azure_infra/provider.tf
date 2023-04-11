provider "azurerm" {
  version         = "= 2.6.0"
  subscription_id = var.azure-subscription-id
  client_id       = var.azure-client-id
  client_secret   = var.azure-client-secret
  tenant_id       = var.azure-tenant-id
  partner_id	  = "5a1e8d63-79c9-418d-b3af-b2a21a557aac-partnercenter"
  features {}
}
