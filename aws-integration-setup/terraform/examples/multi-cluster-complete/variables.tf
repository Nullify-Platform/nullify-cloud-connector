# Simplified Multi-Cluster Example Variables

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

variable "eks_cluster_arns" {
  type        = list(string)
  description = "ARNs of exactly two EKS clusters, primary first (they can be in different regions). This example wires one Kubernetes provider per cluster; add a provider and module block per extra cluster"

  validation {
    condition     = length(var.eks_cluster_arns) == 2
    error_message = "This example deploys to exactly two clusters. For one cluster, use the k8s-resources module with a single Kubernetes provider."
  }
}

variable "scan_mode" {
  type        = string
  description = "collector: in-cluster CronJob with IRSA (default). managed: Nullify lists resources through an EKS access entry and the list-only nullify-readonly ClusterRole, with nothing running in the cluster. both: deploy both"
  default     = "collector"

  validation {
    condition     = contains(["collector", "managed", "both"], var.scan_mode)
    error_message = "scan_mode must be collector, managed or both"
  }
}

variable "nullify_region" {
  type        = string
  description = "Your Nullify region from the configure page (ap-southeast-2, eu-central-1 or us-east-2). Required when scan_mode is managed or both"
  default     = ""
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

variable "nullify_s3_access_point_arn" {
  type        = string
  description = "The S3 access point ARN Nullify provides as the collector upload target (optional). When set, the collectors upload through it"
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
  description = "Container image for the Kubernetes collector"
  default     = "public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.46.0"
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

variable "kms_key_arn" {
  type        = string
  description = "The KMS ARN shown on the Nullify configure page (optional): a key ARN or an alias ARN"
  default     = ""
}
