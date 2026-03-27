output "lb_public_ip" {
  description = "Public IP address of the Azure Load Balancer"
  value       = module.lb.lb_public_ip
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.lb.lb_public_ip}"
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = module.vnet.vnet_id
}

output "vmss_name" {
  description = "Name of the VM Scale Set"
  value       = module.vmss.vmss_name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}
