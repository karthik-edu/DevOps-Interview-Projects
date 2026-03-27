# Project 03 — Production-Grade AWS Infrastructure with Terraform Modules and Remote State

Provisions a VPC + ALB + Auto Scaling Group on AWS using reusable Terraform modules and an S3/DynamoDB remote state backend. One command to deploy, one command to tear down.

## Architecture

```
Internet
    │  HTTP :80
    ▼
┌─────────────────────────────────────────────────────┐
│  VPC  10.0.0.0/16                                   │
│                                                     │
│  Public subnets (2 AZs)                             │
│  ┌─────────────────────────┐                        │
│  │  Application Load       │◄── inbound HTTP        │
│  │  Balancer (ALB)         │                        │
│  └────────────┬────────────┘                        │
│               │ forward                             │
│  Private subnets (2 AZs)                            │
│  ┌─────────────────────────┐                        │
│  │  Auto Scaling Group     │                        │
│  │  (t3.micro × 1–2)       │                        │
│  │  nginx on Amazon Linux  │                        │
│  └─────────────────────────┘                        │
│               │ outbound via                        │
│  ┌────────────▼────────────┐                        │
│  │  NAT Gateway (single)   │──► internet            │
│  └─────────────────────────┘                        │
└─────────────────────────────────────────────────────┘

Remote State: S3 (versioned + encrypted) + DynamoDB (lock table)
```

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.8 |
| AWS CLI | v2 |
| jq | any |

AWS credentials must be configured:
```bash
aws configure          # or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
aws sts get-caller-identity   # verify
```

## Quick Start

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
1. Verify prerequisites and AWS credentials
2. Bootstrap S3 bucket + DynamoDB table for remote state
3. Init, plan, and apply the dev environment
4. Wait for ALB health checks to pass
5. Print the app URL

Total time: ~5 minutes (NAT Gateway and ALB provisioning dominate).

## Project Structure

```
03-terraform-aws-iac/
├── setup.sh                      # One-command bootstrap
├── bootstrap/
│   └── main.tf                   # Creates S3 + DynamoDB backend (local state)
├── modules/
│   ├── vpc/                      # VPC, subnets, IGW, NAT, route tables
│   ├── alb/                      # ALB, target group, HTTP listener
│   └── ec2/                      # Launch template, ASG, security group
└── environments/
    └── dev/
        ├── main.tf               # Calls all three modules
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars      # Dev-specific overrides
```

## Key Interview Points

**Remote state**: S3 bucket with versioning + server-side encryption. DynamoDB provides mutex locking — two engineers running `terraform apply` simultaneously won't corrupt state.

**Module design**: Each module has a single responsibility (VPC, ALB, EC2). Environments compose modules via outputs/inputs — no copy-paste. Adding a staging environment means a new directory calling the same modules with different `terraform.tfvars`.

**Security**: EC2 instances are in private subnets with no public IPs. Their security group only allows inbound HTTP from the ALB security group — not from the internet. Outbound traffic routes through a NAT Gateway.

**Drift detection**: Run `terraform plan` at any time to detect manual changes (e.g. console-edited security groups). The plan shows exactly what Terraform will correct.

## Demo: Simulate Drift

```bash
# Scale ASG manually — simulates an operator bypassing IaC
ASG=$(cd environments/dev && terraform output -raw asg_name)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$ASG" --desired-capacity 5

# Terraform detects drift on next plan
cd environments/dev && terraform plan
# Output: "~ desired_capacity: 5 -> 1"

terraform apply   # restores desired state
```

## Cleanup

```bash
# Destroy application infrastructure first
cd environments/dev && terraform destroy

# Then destroy the remote state backend
cd ../../bootstrap && terraform destroy
```
