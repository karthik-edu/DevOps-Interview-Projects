#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-command bootstrap for Project 03: Terraform Azure IaC
#
# Usage:
#   chmod +x setup.sh && ./setup.sh
#
# Requirements: terraform >= 1.8, azure CLI (az), jq, ssh-keygen
# Azure credentials must be configured: az login
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="terraform-azure-iac"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo "[$(date +%T)] $*"; }
ok()   { echo "[$(date +%T)] ✓ $*"; }
fail() { echo "[$(date +%T)] ✗ $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1. Prerequisite checks
# --------------------------------------------------------------------------- #
log "Checking prerequisites..."
command -v terraform >/dev/null 2>&1 || fail "terraform is not installed"
command -v az        >/dev/null 2>&1 || fail "Azure CLI (az) is not installed"
command -v jq        >/dev/null 2>&1 || fail "jq is not installed"

SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null) || \
  fail "Not logged in to Azure. Run: az login"
TENANT_ID=$(az account show --query tenantId -o tsv)
ok "Azure Subscription: ${SUBSCRIPTION_ID} | Location: ${AZURE_LOCATION}"

TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
ok "Terraform ${TF_VERSION} | Prerequisites satisfied"

# --------------------------------------------------------------------------- #
# 2. SSH key — auto-generate if ~/.ssh/id_rsa.pub doesn't exist
# --------------------------------------------------------------------------- #
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
if [ ! -f "${SSH_KEY_PATH}.pub" ]; then
  log "Generating SSH key pair at ${SSH_KEY_PATH}..."
  ssh-keygen -t rsa -b 4096 -N '' -f "${SSH_KEY_PATH}" >/dev/null
  ok "SSH key generated: ${SSH_KEY_PATH}.pub"
fi
export TF_VAR_ssh_public_key
TF_VAR_ssh_public_key="$(cat "${SSH_KEY_PATH}.pub")"
ok "SSH public key loaded"

# --------------------------------------------------------------------------- #
# 3. Derive globally unique names for Azure Storage Account
#    Storage account names: 3-24 chars, lowercase alphanumeric only
# --------------------------------------------------------------------------- #
# Use a hash of the subscription ID to ensure uniqueness without length issues
SHORT_HASH=$(echo -n "${SUBSCRIPTION_ID}" | sha256sum | cut -c1-8)
STATE_RG="${PROJECT_NAME}-tfstate-rg"
STATE_SA="tfstate${SHORT_HASH}"   # e.g. tfstatea1b2c3d4 (18 chars)
STATE_CONTAINER="tfstate"

# --------------------------------------------------------------------------- #
# 4. Bootstrap remote state backend (Azure Storage Account + Blob Container)
# --------------------------------------------------------------------------- #
log "Bootstrapping remote state backend..."

cd "${WORKSPACE_ROOT}/bootstrap"

export TF_VAR_location="${AZURE_LOCATION}"
export TF_VAR_resource_group_name="${STATE_RG}"
export TF_VAR_storage_account_name="${STATE_SA}"
export TF_VAR_container_name="${STATE_CONTAINER}"

terraform init -input=false -reconfigure >/dev/null
terraform apply -input=false -auto-approve

ok "Remote state backend ready (https://${STATE_SA}.blob.core.windows.net/${STATE_CONTAINER})"

# --------------------------------------------------------------------------- #
# 5. Initialise environment workspace with Azure Blob Storage backend
# --------------------------------------------------------------------------- #
log "Initialising Terraform for environment: ${ENVIRONMENT}..."

cd "${WORKSPACE_ROOT}/environments/${ENVIRONMENT}"

export TF_VAR_location="${AZURE_LOCATION}"
export TF_VAR_environment="${ENVIRONMENT}"

terraform init -input=false -reconfigure \
  -backend-config="resource_group_name=${STATE_RG}" \
  -backend-config="storage_account_name=${STATE_SA}" \
  -backend-config="container_name=${STATE_CONTAINER}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate"

ok "Terraform initialised with Azure Blob Storage backend"

# --------------------------------------------------------------------------- #
# 6. Plan
# --------------------------------------------------------------------------- #
log "Running terraform plan..."
terraform plan -input=false -out=tfplan
ok "Plan complete"

# --------------------------------------------------------------------------- #
# 7. Apply
# --------------------------------------------------------------------------- #
log "Applying infrastructure (this takes ~3-5 min for NAT Gateway and LB)..."
terraform apply -input=false tfplan
ok "Infrastructure deployed"

# --------------------------------------------------------------------------- #
# 8. Verify
# --------------------------------------------------------------------------- #
LB_IP=$(terraform output -raw lb_public_ip 2>/dev/null) || \
  fail "Could not read lb_public_ip from outputs"
ok "Load Balancer IP: ${LB_IP}"

log "Waiting for LB health checks and nginx to start (up to 5 min)..."
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${LB_IP}" 2>/dev/null || echo "000")
  if [ "${HTTP_CODE}" = "200" ]; then
    ok "Load Balancer is serving traffic (HTTP ${HTTP_CODE}, attempt ${i})"
    break
  fi
  [ "${i}" -eq 30 ] && fail "LB not healthy after 5 min (last HTTP code: ${HTTP_CODE})"
  echo "  ... waiting (${i}/30, HTTP ${HTTP_CODE})"
  sleep 10
done

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
VNET_ID=$(terraform output -raw vnet_id 2>/dev/null || echo "N/A")
VMSS_NAME=$(terraform output -raw vmss_name 2>/dev/null || echo "N/A")
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")

echo ""
echo "============================================================"
echo " Project 03 — Terraform Azure IaC is running"
echo "============================================================"
echo "  Environment   : ${ENVIRONMENT}"
echo "  Subscription  : ${SUBSCRIPTION_ID}"
echo "  Location      : ${AZURE_LOCATION}"
echo "  Resource Group: ${RG_NAME}"
echo "  VNet          : ${VNET_ID}"
echo "  VMSS          : ${VMSS_NAME}"
echo "  App URL       : http://${LB_IP}"
echo "  Remote state  : https://${STATE_SA}.blob.core.windows.net/${STATE_CONTAINER}/${ENVIRONMENT}/terraform.tfstate"
echo ""
echo "  To update infrastructure:"
echo "    cd environments/${ENVIRONMENT}"
echo "    terraform plan && terraform apply"
echo ""
echo "  To simulate drift (manually scale VMSS, Terraform self-heals):"
echo "    az vmss scale \\"
echo "      --resource-group ${RG_NAME} \\"
echo "      --name ${VMSS_NAME} \\"
echo "      --new-capacity 5"
echo "    # Terraform drift detected on next plan"
echo ""
echo "  To destroy (avoids ongoing Azure costs):"
echo "    cd environments/${ENVIRONMENT} && terraform destroy"
echo "    cd ../../bootstrap && terraform destroy"
echo "============================================================"
