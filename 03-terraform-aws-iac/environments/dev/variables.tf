variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev / staging / production)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used as a resource prefix"
  type        = string
  default     = "terraform-aws-iac"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for ASG instances"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "ASG minimum instance count"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG maximum instance count"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "ASG desired instance count"
  type        = number
  default     = 1
}
