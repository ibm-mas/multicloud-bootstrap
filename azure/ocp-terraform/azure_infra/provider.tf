terraform {
required_providers {
  azurerm = {
  source  = "hashicorp/azurerm"
  version = "3.21.0"
      }
          }
            }
provider "azurerm" {
  subscription_id = var.azure-subscription-id
  client_id       = var.azure-client-id
  client_secret   = var.azure-client-secret
  tenant_id       = var.azure-tenant-id
  partner_id      = "pid-5a1e8d63-79c9-418d-b3af-b2a21a557aac-partnercenter"
  features {}
}