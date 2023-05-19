provider "azurerm" {
  version         = "= 2.6.0"
  subscription_id = var.azure-subscription-id
  client_id       = var.azure-client-id
  client_secret   = var.azure-client-secret
  tenant_id       = var.azure-tenant-id
  partner_id	  = "a8835dfb-6bdf-4614-be3f-805ef276e05b"
  features {}
}