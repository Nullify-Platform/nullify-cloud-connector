terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0, < 4.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 5.0.0"
    }
  }
}
