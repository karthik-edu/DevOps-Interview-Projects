output "lb_public_ip" {
  description = "Public IP address of the Load Balancer"
  value       = azurerm_public_ip.lb.ip_address
}

output "lb_id" {
  description = "ID of the Azure Load Balancer"
  value       = azurerm_lb.this.id
}

output "backend_pool_id" {
  description = "ID of the backend address pool (referenced by VMSS NIC config)"
  value       = azurerm_lb_backend_address_pool.this.id
}
