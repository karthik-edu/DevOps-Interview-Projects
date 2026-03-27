output "vmss_name" {
  description = "Name of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.this.name
}

output "vmss_id" {
  description = "ID of the VM Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.this.id
}

output "vmss_nsg_id" {
  description = "ID of the VMSS Network Security Group"
  value       = azurerm_network_security_group.vmss.id
}
