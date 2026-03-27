# Project 21 Details

## 1. PROJECT TITLE
Multi-Cloud Infrastructure Provisioning with Terraform Across Azure and GCP

## 2. PROBLEM STATEMENT
A fast-growing engineering organization is experiencing delivery risk, operational inconsistency, and scaling bottlenecks around this capability area. Manual interventions are causing outages, delays, and poor auditability across environments. This project implements a production-ready solution with automation, guardrails, and observability to improve release velocity and reliability.

## 3. TECH STACK
Terraform 1.8.5, AzureRM Provider 3.110.0, Google Provider 5.35, Azure Virtual Network, GCP VPC, Azure Load Balancer, GCP Cloud Load Balancing

## 4. ARCHITECTURE DIAGRAM (ASCII)
`	ext
+-------------+        Commit/Trigger         +----------------------+
| Developer   | ----------------------------> | CI/CD or GitOps Layer|
+-------------+                               +----------+-----------+
                                                          |
                                             +------------+-------------+
                                             |                          |
                                    Provision Azure           Provision GCP
                                             |                          |
                                    +--------+--------+      +----------+--------+
                                    | Azure Platform  |      | GCP Platform      |
                                    | (VNet, VMSS,    |      | (VPC, GKE,        |
                                    |  Load Balancer) |      |  Cloud LB)        |
                                    +--------+--------+      +----------+--------+
                                             |                          |
                                             +------------+-------------+
                                                          |
                                                          | Metrics/Logs/Events
                                                          v
                                                +---------+---------+
                                                | Unified Observability|
                                                | & Security Controls  |
                                                +--------------------+
`

## 5. STEP-BY-STEP EXECUTION GUIDE
1. Bootstrap local workspace.
`ash
mkdir -p ~/devops-series/21-multicloud-terraform-azure-gcp && cd ~/devops-series/21-multicloud-terraform-azure-gcp
`
Expected output:
`	ext
(no output)
`

2. Initialize source control.
`ash
git init -b main
git add .
git commit -m "Initialize project 21"
`
Expected output:
`	ext
Initialized empty Git repository
[main (root-commit) ...] Initialize project 21
`

3. Create environment configuration scaffold.
`ash
mkdir -p infra/azure infra/gcp manifests ci scripts
`
Expected output:
`	ext
(no output)
`

4. Configure provider credentials and validate.
`ash
# Azure authentication
az login
az account set --subscription "<subscription-id>"

# GCP authentication
gcloud auth application-default login
export GOOGLE_PROJECT="<gcp-project-id>"

# Validate Terraform configs for both providers
terraform validate
`
Expected output:
`	ext
Validation successful
`

5. Deploy and verify across both clouds.
`ash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Verify Azure resources
az network vnet list --resource-group multi-cloud-rg

# Verify GCP resources
gcloud compute networks list
`
Expected output:
`	ext
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
`

## 6. INTERVIEW QUESTIONS COVERED
- How would you design and implement Multi-Cloud Infrastructure Provisioning with Terraform Across Azure and GCP in a production environment?
- How do you manage multiple provider credentials securely in a multi-cloud Terraform setup?
- What failure modes are common in this setup, and how do you detect them early?
- Which security controls and least-privilege practices are required in each cloud?
- How do you handle rollback, disaster recovery, and operational runbooks across cloud boundaries?
- How would you scale this architecture for multi-team or multi-environment use?
- What are the key networking differences between Azure Virtual Networks and GCP VPCs when designing cross-cloud connectivity?

## 7. VIDEO TRANSCRIPT
"Welcome back. In this tutorial, we are implementing Multi-Cloud Infrastructure Provisioning with Terraform Across Azure and GCP from scratch as a real-world DevOps project.

You will learn the architecture, the exact execution flow, and the operational checks that interviewers expect from experienced engineers.

Step one, we bootstrap the project repository and create a clean structure with separate directories for Azure and GCP infrastructure. We configure both the AzureRM and Google Terraform providers with least-privilege service principal and service account credentials respectively.

Step two, we define Terraform resources for Azure Virtual Networks, Virtual Machine Scale Sets, and Azure Load Balancers alongside GCP VPCs, Cloud Load Balancing, and GKE clusters. A single Terraform workspace manages both cloud footprints.

Step three, we deploy the stack and verify resource health in both clouds using Azure Monitor and GCP Cloud Monitoring. If something fails, isolate whether the failure is in the Azure or GCP provider, then narrow down to credential scoping, quota limits, or resource naming conflicts.

Step four, we test rollback and confirm we can recover quickly under failure conditions. That resilience mindset is what separates strong DevOps and SRE engineers from script-only operators.

By the end, you have a reusable implementation pattern, a practical interview story, and a project artifact you can showcase on your resume."

## 8. RESUME BULLET POINT
Implemented **Multi-Cloud Infrastructure Provisioning with Terraform Across Azure and GCP** using AzureRM and Google providers in a unified Terraform workspace — enabling consistent provisioning, least-privilege credential management, and centralized observability across cloud platforms.
