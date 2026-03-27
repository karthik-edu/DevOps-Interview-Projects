# Project 33 Details

## 1. PROJECT TITLE
Least-Privilege Azure RBAC Role Assignment and Policy Automation with Terraform

## 2. PROBLEM STATEMENT
A fast-growing engineering organization is experiencing delivery risk, operational inconsistency, and scaling bottlenecks around this capability area. Manual interventions are causing outages, delays, and poor auditability across environments. This project implements a production-ready solution with automation, guardrails, and observability to improve release velocity and reliability.

## 3. TECH STACK
Terraform 1.8.5, AzureRM Provider 3.110.0, Azure RBAC, Azure Policy, Azure Monitor Activity Logs, Microsoft Entra ID (Azure AD)

## 4. ARCHITECTURE DIAGRAM (ASCII)
`	ext
+-------------+        Commit/Trigger         +----------------------+
| Developer   | ----------------------------> | CI/CD or GitOps Layer|
+-------------+                               +----------+-----------+
                                                          |
                                                          | Provision/Deploy/Policy
                                                          v
                                                +---------+---------+
                                                | Azure RBAC &      |
                                                | Policy Engine     |
                                                +---------+---------+
                                                          |
                                                          | Audit/Events
                                                          v
                                                +---------+---------+
                                                | Azure Monitor     |
                                                | Activity Logs     |
                                                +-------------------+
`

## 5. STEP-BY-STEP EXECUTION GUIDE
1. Bootstrap local workspace.
`ash
mkdir -p ~/devops-series/33-azure-rbac-terraform && cd ~/devops-series/33-azure-rbac-terraform
`
Expected output:
`	ext
(no output)
`

2. Initialize source control.
`ash
git init -b main
git add .
git commit -m "Initialize project 33"
`
Expected output:
`	ext
Initialized empty Git repository
[main (root-commit) ...] Initialize project 33
`

3. Create environment configuration scaffold.
`ash
mkdir -p infra manifests ci scripts
`
Expected output:
`	ext
(no output)
`

4. Define custom RBAC roles and policy assignments.
`ash
# Define custom role with least-privilege actions in HCL
# Assign built-in and custom roles to service principals at subscription/resource-group scope
# Attach Azure Policy definitions for guardrails (e.g., allowed regions, required tags)

az login
az account set --subscription "<subscription-id>"
terraform validate
`
Expected output:
`	ext
Validation successful
`

5. Deploy and verify.
`ash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Verify role assignments
az role assignment list --scope /subscriptions/<subscription-id> --output table

# Verify policy compliance
az policy state summarize --subscription <subscription-id>
`
Expected output:
`	ext
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.
`

## 6. INTERVIEW QUESTIONS COVERED
- How would you design and implement Least-Privilege Azure RBAC Role Assignment and Policy Automation with Terraform in a production environment?
- What is the difference between Azure built-in roles and custom RBAC roles, and when would you create a custom role?
- How do Azure Policy and RBAC complement each other for governance?
- What failure modes are common in this setup, and how do you detect them early?
- How do you audit RBAC changes and detect privilege escalation using Azure Monitor Activity Logs?
- How would you scale this architecture for multi-team or multi-subscription use?
- How does Microsoft Entra ID (Azure AD) integrate with Azure RBAC for identity federation?

## 7. VIDEO TRANSCRIPT
"Welcome back. In this tutorial, we are implementing Least-Privilege Azure RBAC Role Assignment and Policy Automation with Terraform from scratch as a real-world DevOps project.

You will learn the architecture, the exact execution flow, and the operational checks that interviewers expect from experienced engineers.

Step one, we bootstrap the project repository and create a clean structure. We authenticate with Azure CLI and configure the AzureRM provider scoped to our target subscription.

Step two, we define custom Azure RBAC roles using the azurerm_role_definition resource, specifying only the actions required by each workload. We then use azurerm_role_assignment to bind these roles to Entra ID service principals at the appropriate management scope — subscription, resource group, or individual resource.

Step three, we attach Azure Policy definitions using azurerm_policy_assignment to enforce guardrails such as allowed regions, mandatory resource tags, and VM SKU restrictions. Azure Policy provides deny-on-deploy enforcement that RBAC alone cannot cover.

Step four, we verify compliance state and audit all role assignments through Azure Monitor Activity Logs. Any privilege escalation or unauthorized assignment attempt is captured and can trigger alerts via Azure Monitor diagnostic settings.

By the end, you have a reusable implementation pattern, a practical interview story, and a project artifact you can showcase on your resume."

## 8. RESUME BULLET POINT
Implemented **Least-Privilege Azure RBAC Role Assignment and Policy Automation with Terraform** using custom role definitions, scoped role assignments via Entra ID, and Azure Policy guardrails — reducing attack surface and ensuring audit-ready governance across subscriptions.
