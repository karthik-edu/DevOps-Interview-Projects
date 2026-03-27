# =============================================================================
# modules/vnet/main.tf
#
# Creates an Azure Virtual Network with:
#   - 2 public subnets  (for Azure Load Balancer frontend)
#   - 2 private subnets (for VMSS instances)
#   - NAT Gateway with public IP (single, cost-optimised for dev/staging)
#   - NAT Gateway associated to all private subnets for outbound internet
# =============================================================================

locals {
  public_subnets  = [for i in range(2) : cidrsubnet(var.vnet_cidr, 8, i)]
  private_subnets = [for i in range(2) : cidrsubnet(var.vnet_cidr, 8, i + 10)]
}

# --------------------------------------------------------------------------- #
# Virtual Network
# --------------------------------------------------------------------------- #
resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = merge(var.tags, { Name = "${var.name}-vnet" })
}

# --------------------------------------------------------------------------- #
# Public subnets — used by the Azure Load Balancer frontend
# --------------------------------------------------------------------------- #
resource "azurerm_subnet" "public" {
  count                = length(local.public_subnets)
  name                 = "${var.name}-public-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.public_subnets[count.index]]
}

# --------------------------------------------------------------------------- #
# Private subnets — used by VMSS instances (no direct public IP)
# --------------------------------------------------------------------------- #
resource "azurerm_subnet" "private" {
  count                = length(local.private_subnets)
  name                 = "${var.name}-private-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.private_subnets[count.index]]
}

# --------------------------------------------------------------------------- #
# NAT Gateway — single instance for cost savings in non-production
# Provides outbound internet access for private subnet VMs (package installs)
# --------------------------------------------------------------------------- #
resource "azurerm_public_ip" "nat" {
  name                = "${var.name}-nat-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, { Name = "${var.name}-nat-ip" })
}

resource "azurerm_nat_gateway" "this" {
  name                = "${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"

  tags = merge(var.tags, { Name = "${var.name}-nat" })
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with every private subnet
resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = length(azurerm_subnet.private)
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
