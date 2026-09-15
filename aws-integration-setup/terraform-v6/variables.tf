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
  description = "ARNs of the EKS clusters whose collector service account the role trusts (required when enable_kubernetes_integration is true). Clusters can be in any region"
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
  description = "The S3 access point ARN Nullify provides as the collector upload target (optional)"
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
  description = "Deprecated and unused: this configuration deploys no collector. Set the schedule on the k8s-resources module instead"
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
  description = "The KMS ARN shown on the Nullify configure page (optional): a key ARN or an alias ARN"
  default     = ""
}

variable "enable_managed_scan" {
  type        = bool
  description = "Create EKS access entries so Nullify's managed scan can list Kubernetes resources with no in-cluster agent"
  default     = false
}

variable "managed_scan_cluster_arns" {
  type        = list(string)
  description = "EKS clusters for the managed scan, in any region of this account"
  default     = []
}

variable "collector_cluster_arns" {
  type        = list(string)
  description = "Override for which clusters eks_managed_scan_access treats as already running the collector, for its duplicate-registration guard. Defaults to eks_cluster_arns when enable_kubernetes_integration is true, since granting the collector's IRSA trust is the closest available signal that a collector is deployed there -- but trust and deployment can diverge: a staged rollout may grant trust ahead of deploying k8s-resources' CronJob (or the Helm chart, or an equivalent manifest) to those clusters, incorrectly blocking their managed scan. It also decouples a collector-to-managed-scan cutover from revoking IRSA trust: set this to eks_cluster_arns minus the cluster being migrated so the guard stops blocking it, and drop the cluster from eks_cluster_arns itself only once the cutover is confirmed. null keeps the default derivation from eks_cluster_arns"
  default     = null
}

variable "managed_scan_authorization" {
  type        = string
  description = "rbac (recommended): the access entry carries managed_scan_kubernetes_group, which you bind to a list-only nullify-readonly ClusterRole. The k8s-resources module applies that ClusterRole with enable_managed_scan_rbac = true; the root has no Kubernetes provider, so apply it separately. admin_view_policy: AmazonEKSAdminViewPolicy, which reads every resource including Secrets and pods/log, and allows exec into pods on EKS 1.34 and earlier"
  default     = "rbac"
}

variable "managed_scan_kubernetes_group" {
  type        = string
  description = "Kubernetes group on the access entries in rbac mode"
  default     = "nullify-readonly"
}

variable "nullify_region" {
  type        = string
  description = "Your Nullify region from the configure page (ap-southeast-2, eu-central-1 or us-east-2). Required when enable_managed_scan is true"
  default     = ""
}
