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

  validation {
    condition     = length(var.external_id) >= 12
    error_message = "External ID must be at least 12 characters for security best practice"
  }
}

variable "nullify_role_arn" {
  type        = string
  description = "The Nullify cross-account role ARN"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.nullify_role_arn))
    error_message = "Must be a valid ARN for an IAM role in the format arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "enable_kubernetes_integration" {
  type        = bool
  description = "Whether the role trusts the in-cluster collector's service account (IRSA) on the clusters in eks_cluster_arns"
  default     = false
}

variable "eks_cluster_arns" {
  type        = list(string)
  description = "ARNs of the EKS clusters whose collector service account the role trusts. Each cluster is looked up in the region in its ARN"
  default     = []

  validation {
    condition     = alltrue([for arn in var.eks_cluster_arns : can(regex("^arn:aws:eks:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9][A-Za-z0-9_-]*$", arn))])
    error_message = "Each entry must be an EKS cluster ARN: arn:aws:eks:<region>:<account-id>:cluster/<name>"
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

variable "nullify_s3_access_point_arn" {
  type        = string
  description = "The S3 access point ARN Nullify provides as the collector upload target (optional). When set, the role may also put objects under <access point ARN>/object/k8s-collector/*; the s3_bucket_name grants stay"
  default     = ""

  validation {
    condition     = var.nullify_s3_access_point_arn == "" || can(regex("^arn:aws:s3:[a-z0-9-]+:[0-9]{12}:accesspoint/[a-z0-9-]{3,50}$", var.nullify_s3_access_point_arn))
    error_message = "Must be empty or an S3 access point ARN: arn:aws:s3:<region>:<account-id>:accesspoint/<name>"
  }
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
  description = "Deprecated and unused: set the collector schedule on the k8s-resources module. Kept so callers that pass it keep working"
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
  description = "The KMS ARN shown on the Nullify configure page (optional): a key ARN, including multi-Region key/mrk-... keys, or an alias ARN. IAM ignores alias ARNs, so the KMS policy grants this ARN and key/* in the same Nullify account and region. Nullify's key policy decides which of those keys the role can use"
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:(key/(mrk-)?[a-f0-9-]+|alias/[A-Za-z0-9/_-]+)$", var.kms_key_arn))
    error_message = "Must be empty, a KMS key ARN (arn:aws:kms:<region>:<account-id>:key/<key-id>) or a KMS alias ARN (arn:aws:kms:<region>:<account-id>:alias/<name>)"
  }
}
