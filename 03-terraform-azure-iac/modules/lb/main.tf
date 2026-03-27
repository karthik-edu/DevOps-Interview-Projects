# =============================================================================
# modules/lb/main.tf
#
# Creates a public-facing Azure Load Balancer (Standard SKU) with:
#   - Static public IP
#   - Backend address pool (VMSS instances self-register via NIC config)
#   - HTTP health probe on port 80
#   - LB rule: TCP 80 → backend pool
# =============================================================================

# --------------------------------------------------------------------------- #
# Public IP for the Load Balancer frontend
# --------------------------------------------------------------------------- #
resource "azurerm_public_ip" "lb" {
  name                = "${var.name}-lb-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, { Name = "${var.name}-lb-ip" })
}

# --------------------------------------------------------------------------- #
# Azure Load Balancer — Standard SKU required for zone resilience and VMSS
# --------------------------------------------------------------------------- #
resource "azurerm_lb" "this" {
  name                = "${var.name}-lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = merge(var.tags, { Name = "${var.name}-lb" })
}

# --------------------------------------------------------------------------- #
# Backend Address Pool — VMSS registers instances here via NIC ip_configuration
# --------------------------------------------------------------------------- #
resource "azurerm_lb_backend_address_pool" "this" {
  name            = "${var.name}-backend-pool"
  loadbalancer_id = azurerm_lb.this.id
}

# --------------------------------------------------------------------------- #
# Health Probe — HTTP GET / on port 80; 2 successes = healthy, 3 fails = unhealthy
# --------------------------------------------------------------------------- #
resource "azurerm_lb_probe" "http" {
  name                = "${var.name}-http-probe"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  number_of_probes    = 3
  interval_in_seconds = 15
}

# --------------------------------------------------------------------------- #
# LB Rule — forward TCP :80 from frontend to backend pool
# --------------------------------------------------------------------------- #
resource "azurerm_lb_rule" "http" {
  name                           = "${var.name}-http-rule"
  loadbalancer_id                = azurerm_lb.this.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.http.id
  idle_timeout_in_minutes        = 4
  enable_floating_ip             = false
}
