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

variable "eks_cluster_arn" {
  type        = string
  description = "ARN of the EKS cluster Nullify scans. The role and access entry are created in this cluster's account and region"

  validation {
    condition     = can(regex("^arn:aws:eks:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9][A-Za-z0-9_-]*$", var.eks_cluster_arn))
    error_message = "Must be an EKS cluster ARN: arn:aws:eks:<region>:<account-id>:cluster/<name>"
  }
}

variable "nullify_region" {
  type        = string
  description = "Your Nullify region from the configure page (ap-southeast-2, eu-central-1 or us-east-2). It selects the egress IPs the cluster's public endpoint must admit"
}

variable "authorization" {
  type        = string
  description = "rbac (recommended) or admin_view_policy. admin_view_policy grants get, list and watch on every resource, including Secrets, custom resources and pods/log, and on EKS 1.34 and earlier allows exec into pods"
  default     = "rbac"
}

variable "kubernetes_group_name" {
  type        = string
  description = "Kubernetes group on the access entry, bound to the nullify-readonly ClusterRole in rbac mode"
  default     = "nullify-readonly"
}

variable "manage_rbac" {
  type        = bool
  description = "In rbac mode, create the nullify-readonly ClusterRole and binding with the Kubernetes provider. Set false when GitOps or Helm applies them"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to AWS resources"
  default = {
    ManagedBy = "Terraform"
    Purpose   = "NullifyIntegration"
  }
}
