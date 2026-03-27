# =============================================================================
# environments/dev/main.tf
#
# Dev environment: calls all three modules with dev-sized resources.
# Remote state backend is configured at init time via setup.sh using
# Azure Blob Storage (native blob lease locking — no DynamoDB needed).
# =============================================================================

terraform {
  required_version = ">= 1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  backend "azurerm" {
    # resource_group_name, storage_account_name, container_name, key
    # are passed via -backend-config flags in setup.sh
    # so this file stays environment-agnostic.
  }
}

provider "azurerm" {
  features {}
}

locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --------------------------------------------------------------------------- #
# Resource Group — top-level container for all environment resources in Azure
# --------------------------------------------------------------------------- #
resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location

  tags = local.common_tags
}

# --------------------------------------------------------------------------- #
# Modules
# --------------------------------------------------------------------------- #
module "vnet" {
  source              = "../../modules/vnet"
  name                = local.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = var.vnet_cidr
  tags                = local.common_tags
}

module "lb" {
  source              = "../../modules/lb"
  name                = local.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

module "vmss" {
  source              = "../../modules/vmss"
  name                = local.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  private_subnet_ids  = module.vnet.private_subnet_ids
  lb_backend_pool_id  = module.lb.backend_pool_id
  ssh_public_key      = var.ssh_public_key
  environment         = var.environment
  vm_size             = var.vm_size
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  tags                = local.common_tags
}
