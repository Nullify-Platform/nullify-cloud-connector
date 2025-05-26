# Basic Example: Nullify AWS Integration (AWS IAM only)

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
  region = "ap-southeast-2"
}

module "nullify_aws_integration" {
  source = "../../modules/nullify-aws-integration"

  # Required variables
  customer_name    = "acme-corp"
  external_id      = "your-external-id-from-nullify"
  nullify_role_arn = "arn:aws:iam::NULLIFY-ACCOUNT-ID:role/NULLIFY-ROLE-NAME"

  # Optional - using defaults for most values
  aws_region = "ap-southeast-2"

  # Custom tags
  tags = {
    Environment = "production"
    Team        = "security"
    Project     = "nullify-integration"
  }
}

output "role_arn" {
  description = "ARN of the created IAM role"
  value       = module.nullify_aws_integration.role_arn
}

output "deployment_summary" {
  description = "Summary of the deployment"
  value       = module.nullify_aws_integration.deployment_summary
} 