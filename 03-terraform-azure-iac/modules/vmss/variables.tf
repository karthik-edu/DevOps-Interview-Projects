variable "name" {
  description = "Name prefix applied to all resources"
  type        = string
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VMSS instances"
  type        = list(string)
}

variable "lb_backend_pool_id" {
  description = "ID of the LB backend address pool to register VMSS instances with"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the azureuser admin account"
  type        = string
}

variable "environment" {
  description = "Environment name shown in the nginx demo page"
  type        = string
  default     = "dev"
}

variable "vm_size" {
  description = "Azure VM size for VMSS instances (e.g. Standard_B1s)"
  type        = string
  default     = "Standard_B1s"
}

variable "min_size" {
  description = "Minimum number of VMSS instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of VMSS instances"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Initial number of VMSS instances"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
