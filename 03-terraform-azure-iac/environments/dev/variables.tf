variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev / staging / production)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used as a resource prefix"
  type        = string
  default     = "terraform-azure-iac"
}

variable "vnet_cidr" {
  description = "Address space for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vm_size" {
  description = "Azure VM size for VMSS instances"
  type        = string
  default     = "Standard_B1s"
}

variable "ssh_public_key" {
  description = "SSH public key for the azureuser admin account on VMSS instances"
  type        = string
}

variable "min_size" {
  description = "VMSS minimum instance count"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "VMSS maximum instance count"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "VMSS initial instance count"
  type        = number
  default     = 1
}
