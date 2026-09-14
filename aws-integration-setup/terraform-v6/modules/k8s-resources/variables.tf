variable "enable_collector" {
  type        = bool
  description = "Deploy the in-cluster collector: namespace, IRSA service account, RBAC and CronJob"
  default     = true
}

variable "enable_managed_scan_rbac" {
  type        = bool
  description = "Create the list-only ClusterRole and ClusterRoleBinding for Nullify's managed EKS scan, bound to managed_scan_kubernetes_group. Pair it with the eks-managed-scan-access module in rbac mode. Applying it needs rights to grant every listed permission, which in practice means cluster-admin"
  default     = false
}

variable "managed_scan_kubernetes_group" {
  type        = string
  description = "Kubernetes group on the Nullify access entry that the managed-scan ClusterRole is bound to"
  default     = "nullify-readonly"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$", var.managed_scan_kubernetes_group))
    error_message = "Lowercase letters, digits, '.' and '-' only (max 63 characters). ':' is not allowed, which excludes system: groups."
  }
}

variable "managed_scan_cluster_role_name" {
  type        = string
  description = "Name of the managed-scan ClusterRole. The default matches the nullify-k8s-readonly-access Helm chart and manifests/nullify-readonly-rbac.yaml"
  default     = "nullify-readonly"
}

variable "managed_scan_cluster_role_binding_name" {
  type        = string
  description = "Name of the managed-scan ClusterRoleBinding"
  default     = "nullify-readonly"
}

variable "iam_role_arn" {
  type        = string
  description = "The ARN of the IAM role for the collector service account annotation (required when enable_collector is true)"
  default     = ""
}

variable "service_account_name" {
  type        = string
  description = "The name of the Kubernetes service account"
  default     = "nullify-k8s-collector-sa"
}

variable "s3_bucket_name" {
  type        = string
  description = "The collector's S3 upload target: the bucket name, or the S3 access point ARN Nullify provides"
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "The AWS region"
  default     = "ap-southeast-2"
}

variable "kubernetes_namespace" {
  type        = string
  description = "The Kubernetes namespace for Nullify resources"
  default     = "nullify"
}

variable "collector_image" {
  type        = string
  description = "Container image for the Kubernetes collector. Defaults to a pinned tag of Nullify's ECR Public image"
  default     = "public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.45.0"
}

variable "cronjob_schedule" {
  type        = string
  description = "Cron schedule for the Kubernetes collector job"
  default     = "0 0 * * *"
}

variable "kms_key_arn" {
  type        = string
  description = "The KMS ARN shown on the Nullify configure page (optional): a key ARN or an alias ARN"
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:(key/(mrk-)?[a-f0-9-]+|alias/[A-Za-z0-9/_-]+)$", var.kms_key_arn))
    error_message = "Must be empty, a KMS key ARN (arn:aws:kms:<region>:<account-id>:key/<key-id>) or a KMS alias ARN (arn:aws:kms:<region>:<account-id>:alias/<name>)"
  }
}

variable "enable_debug" {
  type        = bool
  description = "Enable debug logging for troubleshooting"
  default     = false
}
