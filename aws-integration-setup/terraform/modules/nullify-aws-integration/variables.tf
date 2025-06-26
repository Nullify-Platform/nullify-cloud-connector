variable "customer_name" {
  type        = string
  description = "The name of the customer to create the role for"
  
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

variable "enable_kubernetes_integration" {
  type        = bool
  description = "Whether to enable Kubernetes integration resources"
  default     = false
}

variable "eks_cluster_arns" {
  type        = list(string)
  description = "List of ARNs of EKS clusters to integrate with (OIDC provider IDs will be fetched automatically)"
  default     = []

  validation {
    condition     = !var.enable_kubernetes_integration || (var.enable_kubernetes_integration && length(var.eks_cluster_arns) > 0)
    error_message = "When Kubernetes integration is enabled, you must provide at least one cluster ARN in eks_cluster_arns"
  }
}

variable "aws_region" {
  type        = string
  description = "The AWS region where resources are deployed"
  default     = "ap-southeast-2"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for storing scan results (optional, provided by Nullify if needed)"
  default     = ""
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
    ManagedBy = "Terraform"
    Purpose   = "NullifyIntegration"
  }
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key for key management operations (optional, provided by Nullify if needed)"
  default     = ""
} 