# =============================================================================
# bootstrap/main.tf — One-time remote state backend setup
#
# Creates the S3 bucket and DynamoDB table that all environment workspaces
# use as their Terraform backend. This module itself uses local state
# (intentionally — it is the chicken that lays the remote-state egg).
#
# Run via setup.sh; do NOT run manually unless you know what you are doing.
# =============================================================================

terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.58"
    }
  }
  # Local state is correct here — this module bootstraps the remote backend.
}

variable "aws_region"   { type = string; default = "us-east-1" }
variable "state_bucket" { type = string }
variable "lock_table"   { type = string }

provider "aws" {
  region = var.aws_region
}

# --------------------------------------------------------------------------- #
# S3 bucket for Terraform state files
# --------------------------------------------------------------------------- #
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket

  # Allow destroy during demo teardown; set to true in real production.
  force_destroy = true

  tags = {
    Project   = "terraform-aws-iac"
    ManagedBy = "terraform"
    Purpose   = "remote-state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --------------------------------------------------------------------------- #
# DynamoDB table for state locking
# --------------------------------------------------------------------------- #
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "terraform-aws-iac"
    ManagedBy = "terraform"
    Purpose   = "state-locking"
  }
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "lock_table"   { value = aws_dynamodb_table.lock.name }
