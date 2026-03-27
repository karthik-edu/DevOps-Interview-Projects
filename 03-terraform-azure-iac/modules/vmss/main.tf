# =============================================================================
# modules/vmss/main.tf
#
# Creates an Azure Linux VM Scale Set running nginx in private subnets:
#   - Network Security Group (inbound HTTP:80 from AzureLoadBalancer tag only)
#   - Linux VMSS (Ubuntu 22.04 LTS) registered to the LB backend pool
#   - Azure Monitor Autoscale: scale out >75% CPU, scale in <25% CPU
# =============================================================================

# --------------------------------------------------------------------------- #
# Network Security Group — inbound HTTP from LB only, all egress via NAT GW
# --------------------------------------------------------------------------- #
resource "azurerm_network_security_group" "vmss" {
  name                = "${var.name}-vmss-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "allow-http-from-lb"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, { Name = "${var.name}-vmss-nsg" })
}

# --------------------------------------------------------------------------- #
# Linux VM Scale Set — Ubuntu 22.04 LTS, nginx served via custom_data
# --------------------------------------------------------------------------- #
resource "azurerm_linux_virtual_machine_scale_set" "this" {
  name                = "${var.name}-vmss"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.vm_size
  instances           = var.desired_capacity

  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  # Ubuntu 22.04 LTS — equivalent to Amazon Linux 2023 for demo workloads
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Install nginx and serve a demo page identifying the environment
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable --now nginx
    cat > /var/www/html/index.html <<HTML
    <html><body style="font-family:sans-serif;padding:2rem">
    <h1>Project 03 &mdash; Terraform Azure IaC</h1>
    <p><strong>Environment:</strong> ${var.environment}</p>
    <p><strong>VM size:</strong> ${var.vm_size}</p>
    </body></html>
    HTML
  EOF
  )

  network_interface {
    name    = "${var.name}-nic"
    primary = true

    network_security_group_id = azurerm_network_security_group.vmss.id

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = var.private_subnet_ids[0]
      load_balancer_backend_address_pool_ids = [var.lb_backend_pool_id]
    }
  }

  upgrade_mode = "Manual"

  tags = merge(var.tags, { Name = "${var.name}-vmss" })

  # Always create new VMSS before destroying old one for zero-downtime updates
  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------------------- #
# Azure Monitor Autoscale — CPU-based scale out/in rules
# Equivalent to AWS Auto Scaling Group policies
# --------------------------------------------------------------------------- #
resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "${var.name}-autoscale"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.this.id

  profile {
    name = "default"

    capacity {
      default = var.desired_capacity
      minimum = var.min_size
      maximum = var.max_size
    }

    # Scale OUT when avg CPU > 75% for 5 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale IN when avg CPU < 25% for 5 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.tags
}
