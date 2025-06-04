# Simplified Multi-Cluster Example Variables

variable "customer_name" {
  type        = string
  description = "The name of the customer to create the role for"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.customer_name))
    error_message = "Customer name must start with a letter and can only contain letters, numbers, underscores, and hyphens"
  }
  default = "test"
}

variable "external_id" {
  type        = string
  description = "The external ID for the role (provided by Nullify)"
  default = "test"
}

variable "nullify_role_arn" {
  type        = string
  description = "The Nullify cross-account role ARN"
  default = "arn:aws:iam::521464361009:role/alex-aws-access-websocket-apigw"
}

variable "eks_cluster_arns" {
  type        = list(string)
  description = "List of ARNs of EKS clusters to integrate with (can be from different regions)"

  validation {
    condition     = length(var.eks_cluster_arns) > 0
    error_message = "You must provide at least one cluster ARN."
  }
  default = [
    "arn:aws:eks:ap-southeast-2:521464361009:cluster/nullify-k8s-collector",
    "arn:aws:eks:ap-southeast-2:521464361009:cluster/curious-alternative-badger"
  ]
}

variable "aws_region" {
  type        = string
  description = "The primary AWS region for the integration (where IAM resources are created)"
  default     = "ap-southeast-2"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for storing scan results (optional)"
  default     = ""
}

variable "kubernetes_namespace" {
  type        = string
  description = "The Kubernetes namespace for Nullify resources"
  default     = "nullify"
}

variable "cronjob_schedule" {
  type        = string
  description = "Cron schedule for the Kubernetes collector job"
  default     = "*/5 * * * *"
}

variable "collector_image" {
  type        = string
  description = "Docker image for the Kubernetes collector"
  default     = "nullify/k8s-collector:latest"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to AWS resources"
  default = {
    ManagedBy   = "Terraform"
    Purpose     = "NullifyIntegration"
    Environment = "Production"
  }
} 