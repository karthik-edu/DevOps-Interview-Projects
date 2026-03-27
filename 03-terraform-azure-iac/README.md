# Project 03 — Production-Grade Azure Infrastructure with Terraform Modules and Remote State

Provisions a Virtual Network + Azure Load Balancer + VM Scale Set on Azure using reusable Terraform modules and an Azure Blob Storage remote state backend. One command to deploy, one command to tear down.

## Architecture

```
Internet
    │  HTTP :80
    ▼
┌─────────────────────────────────────────────────────┐
│  Virtual Network  10.0.0.0/16                       │
│                                                     │
│  Public subnets (x2)                                │
│  ┌─────────────────────────┐                        │
│  │  Azure Load Balancer    │◄── inbound HTTP        │
│  │  (Standard SKU)         │                        │
│  └────────────┬────────────┘                        │
│               │ forward                             │
│  Private subnets (x2)                               │
│  ┌─────────────────────────┐                        │
│  │  VM Scale Set (VMSS)    │                        │
│  │  (Standard_B1s × 1–3)   │                        │
│  │  nginx on Ubuntu 22.04  │                        │
│  └─────────────────────────┘                        │
│               │ outbound via                        │
│  ┌────────────▼────────────┐                        │
│  │  NAT Gateway (single)   │──► internet            │
│  └─────────────────────────┘                        │
└─────────────────────────────────────────────────────┘

Remote State: Azure Blob Storage (versioned, private)
              Native blob lease locking — no DynamoDB equivalent needed
```

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.8 |
| Azure CLI | latest |
| jq | any |

Azure credentials must be configured:
```bash
az login
az account show   # verify
```

## Quick Start

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
1. Verify prerequisites and Azure login
2. Auto-generate SSH key if `~/.ssh/id_rsa.pub` doesn't exist
3. Bootstrap Azure Storage Account + Blob Container for remote state
4. Init, plan, and apply the dev environment
5. Wait for LB health checks to pass
6. Print the app URL

Total time: ~3-5 minutes (NAT Gateway and VMSS provisioning dominate).

## Project Structure

```
03-terraform-azure-iac/
├── setup.sh                      # One-command bootstrap
├── bootstrap/
│   └── main.tf                   # Creates Storage Account + Blob Container (local state)
├── modules/
│   ├── vnet/                     # VNet, subnets, NAT Gateway
│   ├── lb/                       # Azure Load Balancer, backend pool, health probe, LB rule
│   └── vmss/                     # Linux VMSS, NSG, Azure Monitor autoscale
└── environments/
    └── dev/
        ├── main.tf               # Resource Group + calls all three modules
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars      # Dev-specific overrides
```

## AWS → Azure Mapping

| AWS Resource | Azure Equivalent |
|---|---|
| VPC | Virtual Network (VNet) |
| Public/Private Subnet | Azure Subnet |
| Internet Gateway | Built-in VNet internet routing |
| NAT Gateway | Azure NAT Gateway |
| Application Load Balancer | Azure Load Balancer (Standard SKU) |
| Target Group + Health Check | Backend Pool + LB Probe |
| Auto Scaling Group (ASG) | VM Scale Set (VMSS) |
| Launch Template | VMSS image + custom_data |
| CloudWatch autoscale | Azure Monitor Autoscale |
| S3 + DynamoDB (state) | Azure Blob Storage (native lease locking) |
| Security Group | Network Security Group (NSG) |

## Key Interview Points

**Remote state**: Azure Blob Storage with versioning enabled. Blob leases provide native state locking — two engineers running `terraform apply` simultaneously cannot corrupt state. No separate locking resource (like DynamoDB) is required.

**Module design**: Each module has a single responsibility (VNet, LB, VMSS). Environments compose modules via outputs/inputs — no copy-paste. Adding a staging environment means a new directory calling the same modules with different `terraform.tfvars`.

**Security**: VMSS instances are in private subnets with no public IPs. Their NSG only allows inbound HTTP from the `AzureLoadBalancer` service tag — not from the internet. Outbound traffic routes through a NAT Gateway.

**Autoscale**: Azure Monitor Autoscale scales the VMSS out when average CPU > 75% for 5 minutes, and in when < 25%. Equivalent to AWS Auto Scaling Group policies.

**Drift detection**: Run `terraform plan` at any time to detect manual changes (e.g. portal-edited NSG rules). The plan shows exactly what Terraform will correct.

## Demo: Simulate Drift

```bash
# Scale VMSS manually — simulates an operator bypassing IaC
RG=$(cd environments/dev && terraform output -raw resource_group_name)
VMSS=$(cd environments/dev && terraform output -raw vmss_name)

az vmss scale \
  --resource-group "$RG" \
  --name "$VMSS" \
  --new-capacity 5

# Terraform detects drift on next plan
cd environments/dev && terraform plan
# Output: "~ instances: 5 -> 1"

terraform apply   # restores desired state
```

## Cleanup

```bash
# Destroy application infrastructure first
cd environments/dev && terraform destroy

# Then destroy the remote state backend
cd ../../bootstrap && terraform destroy
```
