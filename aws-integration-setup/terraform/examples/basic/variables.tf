variable "customer_name" {
  type        = string
  description = "The name of the customer to create the role for"
  default     = "acme-corp"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.customer_name))
    error_message = "Customer name must start with a letter and can only contain letters, numbers, underscores, and hyphens"
  }
}

variable "external_id" {
  type        = string
  description = "The external ID for the role (provided by Nullify)"
}

variable "nullify_role_arn" {
  type        = string
  description = "The Nullify cross-account role ARN"
}

variable "aws_region" {
  type        = string
  description = "The AWS region where resources are deployed"
  default     = "ap-southeast-2"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for storing scan results (optional)"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to AWS resources"
  default = {
    Environment = "production"
    Team        = "security"
    Project     = "nullify-integration"
    ManagedBy   = "Terraform"
  }
} 