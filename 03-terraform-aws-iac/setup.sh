#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-command bootstrap for Project 03: Terraform AWS IaC
#
# Usage:
#   chmod +x setup.sh && ./setup.sh
#
# Requirements: terraform >= 1.8, aws CLI v2, jq
# AWS credentials must be configured (aws configure or environment variables)
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="terraform-aws-iac"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo "[$(date +%T)] $*"; }
ok()   { echo "[$(date +%T)] ✓ $*"; }
fail() { echo "[$(date +%T)] ✗ $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1. Prerequisite checks
# --------------------------------------------------------------------------- #
log "Checking prerequisites..."
command -v terraform >/dev/null 2>&1 || fail "terraform is not installed"
command -v aws       >/dev/null 2>&1 || fail "aws CLI is not installed"
command -v jq        >/dev/null 2>&1 || fail "jq is not installed"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
  fail "AWS credentials not configured. Run: aws configure"
ok "AWS Account: ${AWS_ACCOUNT_ID} | Region: ${AWS_REGION}"

TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
ok "Terraform ${TF_VERSION} | Prerequisites satisfied"

# Derive a unique, deterministic bucket name from account + region
STATE_BUCKET="${PROJECT_NAME}-state-${AWS_ACCOUNT_ID}-${AWS_REGION}"
LOCK_TABLE="${PROJECT_NAME}-state-lock"

# --------------------------------------------------------------------------- #
# 2. Bootstrap remote state backend (S3 + DynamoDB)
# --------------------------------------------------------------------------- #
log "Bootstrapping remote state backend..."

cd "${WORKSPACE_ROOT}/bootstrap"

export TF_VAR_state_bucket="${STATE_BUCKET}"
export TF_VAR_lock_table="${LOCK_TABLE}"
export TF_VAR_aws_region="${AWS_REGION}"

terraform init -input=false -reconfigure >/dev/null
terraform apply -input=false -auto-approve

ok "Remote state backend ready (s3://${STATE_BUCKET})"

# --------------------------------------------------------------------------- #
# 3. Initialise environment workspace with S3 backend
# --------------------------------------------------------------------------- #
log "Initialising Terraform for environment: ${ENVIRONMENT}..."

cd "${WORKSPACE_ROOT}/environments/${ENVIRONMENT}"

export TF_VAR_aws_region="${AWS_REGION}"
export TF_VAR_environment="${ENVIRONMENT}"

terraform init -input=false -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${LOCK_TABLE}" \
  -backend-config="encrypt=true"

ok "Terraform initialised with S3 backend"

# --------------------------------------------------------------------------- #
# 4. Plan
# --------------------------------------------------------------------------- #
log "Running terraform plan..."
terraform plan -input=false -out=tfplan
ok "Plan complete"

# --------------------------------------------------------------------------- #
# 5. Apply
# --------------------------------------------------------------------------- #
log "Applying infrastructure (this takes ~5 min for NAT Gateway and ALB)..."
terraform apply -input=false tfplan
ok "Infrastructure deployed"

# --------------------------------------------------------------------------- #
# 6. Verify
# --------------------------------------------------------------------------- #
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null) || \
  fail "Could not read alb_dns_name from outputs"
ok "ALB endpoint: http://${ALB_DNS}"

log "Waiting for ALB health checks to pass (up to 5 min)..."
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}" 2>/dev/null || echo "000")
  if [ "${HTTP_CODE}" = "200" ]; then
    ok "ALB is serving traffic (HTTP ${HTTP_CODE}, attempt ${i})"
    break
  fi
  [ "${i}" -eq 30 ] && fail "ALB not healthy after 5 min (last HTTP code: ${HTTP_CODE})"
  echo "  ... waiting (${i}/30, HTTP ${HTTP_CODE})"
  sleep 10
done

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
ASG_NAME=$(terraform output -raw asg_name 2>/dev/null || echo "N/A")

echo ""
echo "============================================================"
echo " Project 03 — Terraform AWS IaC is running"
echo "============================================================"
echo "  Environment : ${ENVIRONMENT}"
echo "  AWS Account : ${AWS_ACCOUNT_ID} (${AWS_REGION})"
echo "  VPC         : ${VPC_ID}"
echo "  ASG         : ${ASG_NAME}"
echo "  App URL     : http://${ALB_DNS}"
echo "  Remote state: s3://${STATE_BUCKET}/${ENVIRONMENT}/terraform.tfstate"
echo ""
echo "  To update infrastructure:"
echo "    cd environments/${ENVIRONMENT}"
echo "    terraform plan && terraform apply"
echo ""
echo "  To simulate drift (scale ASG manually, ArgoCD self-heals):"
echo "    aws autoscaling set-desired-capacity \\"
echo "      --auto-scaling-group-name ${ASG_NAME} --desired-capacity 5"
echo "    # Terraform drift detected on next plan"
echo ""
echo "  To destroy (avoids ongoing AWS costs):"
echo "    cd environments/${ENVIRONMENT} && terraform destroy"
echo "    cd ../../bootstrap && terraform destroy"
echo "============================================================"
