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

variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS cluster to integrate with"
}

variable "kubernetes_namespace" {
  type        = string
  description = "The Kubernetes namespace for Nullify resources"
  default     = "nullify"
}

variable "service_account_name" {
  type        = string
  description = "The name of the Kubernetes service account"
  default     = "nullify-k8s-collector-sa"
}

variable "cronjob_schedule" {
  type        = string
  description = "Cron schedule for the Kubernetes collector job"
  default     = "0 0 * * *"
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