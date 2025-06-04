# Basic Example: Nullify AWS Integration (AWS resources only)
# This example shows the minimal setup for AWS integration without Kubernetes

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "nullify_aws_integration" {
  source = "../../modules/nullify-aws-integration"

  # Required variables
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn

  # AWS Configuration
  aws_region     = var.aws_region
  s3_bucket_name = var.s3_bucket_name

  # Kubernetes integration disabled - no Kubernetes provider needed
  enable_kubernetes_integration = false

  # Custom tags
  tags = var.tags
}

output "role_arn" {
  description = "ARN of the created IAM role"
  value       = module.nullify_aws_integration.role_arn
}

output "deployment_summary" {
  description = "Summary of the deployment"
  value       = module.nullify_aws_integration.deployment_summary
} 