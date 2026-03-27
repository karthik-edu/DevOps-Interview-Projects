# =============================================================================
# bootstrap/main.tf — One-time remote state backend setup
#
# Creates the Azure Storage Account and Blob Container that all environment
# workspaces use as their Terraform backend. This module itself uses local
# state (intentionally — it is the chicken that lays the remote-state egg).
#
# Azure Blob Storage provides native state locking via blob leases —
# no separate locking resource (like DynamoDB) is required.
#
# Run via setup.sh; do NOT run manually unless you know what you are doing.
# =============================================================================

terraform {
  required_version = ">= 1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
  # Local state is correct here — this module bootstraps the remote backend.
}

variable "location"             { type = string; default = "eastus" }
variable "resource_group_name"  { type = string }
variable "storage_account_name" { type = string }
variable "container_name"       { type = string; default = "tfstate" }

provider "azurerm" {
  features {}
}

# --------------------------------------------------------------------------- #
# Resource Group for Terraform state resources
# --------------------------------------------------------------------------- #
resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Project   = "terraform-azure-iac"
    ManagedBy = "terraform"
    Purpose   = "remote-state"
  }
}

# --------------------------------------------------------------------------- #
# Storage Account — holds the state blob container
# Must be globally unique, 3-24 chars, lowercase alphanumeric only.
# --------------------------------------------------------------------------- #
resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  # Deny all public blob access
  allow_nested_items_to_be_public = false

  tags = {
    Project   = "terraform-azure-iac"
    ManagedBy = "terraform"
    Purpose   = "remote-state"
  }
}

# --------------------------------------------------------------------------- #
# Blob Container — stores .tfstate files
# Locking is handled automatically by blob leases (no DynamoDB equivalent needed)
# --------------------------------------------------------------------------- #
resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

output "storage_account_name" { value = azurerm_storage_account.tfstate.name }
output "container_name"       { value = azurerm_storage_container.tfstate.name }
output "resource_group_name"  { value = azurerm_resource_group.tfstate.name }
