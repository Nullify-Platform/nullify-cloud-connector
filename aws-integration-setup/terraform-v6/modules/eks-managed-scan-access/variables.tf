variable "principal_arn" {
  type        = string
  description = "ARN of the Nullify read-only role (module.nullify_aws_integration.role_arn). Nullify assumes it in the cluster's own account, so it must be in the same account as the clusters"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.principal_arn))
    error_message = "principal_arn must be an IAM role ARN: arn:aws:iam::<account-id>:role/<name>"
  }
}

variable "principal_unique_id" {
  type        = string
  description = "unique_id of the role (module.nullify_aws_integration.role_unique_id). EKS ties an access entry to the role's ID, so a recreated role with the same ARN is not authorized by the old entry; when this value changes, the entries are replaced"
  default     = ""
}

variable "cluster_arns" {
  type        = list(string)
  description = "ARNs of the EKS clusters Nullify scans. Each cluster is read and granted access in the region from its ARN. The clusters must already exist and their ARNs must be known at plan time: they drive for_each"

  validation {
    condition     = length(var.cluster_arns) > 0 && alltrue([for arn in var.cluster_arns : can(regex("^arn:aws:eks:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9][A-Za-z0-9_-]*$", arn))])
    error_message = "Provide at least one EKS cluster ARN: arn:aws:eks:<region>:<account-id>:cluster/<name>. Every ARN must be known at plan time and its cluster must already exist: they drive for_each and a data source lookup, so a cluster created in the same apply has to be applied first (see 'Ordering' in the README)."
  }
}

variable "authorization" {
  type        = string
  description = "How Kubernetes authorizes the access entry. rbac (recommended): the entry carries kubernetes_group_name; bind it to a list-only nullify-readonly ClusterRole, which k8s-resources applies with enable_managed_scan_rbac = true. admin_view_policy: associates AmazonEKSAdminViewPolicy at cluster scope and needs no Kubernetes objects. WARNING: AmazonEKSAdminViewPolicy grants get, list and watch on every resource, including Secrets, custom resources and pods/log; on EKS 1.34 and earlier get pods/exec is enough to exec into pods; and its grants do not show in kubectl auth can-i --list"
  default     = "rbac"

  validation {
    condition     = contains(["rbac", "admin_view_policy"], var.authorization)
    error_message = "authorization must be rbac or admin_view_policy. AmazonEKSViewPolicy is not offered: it cannot list nodes, persistent volumes, Secrets, RBAC or admission objects."
  }
}

variable "kubernetes_group_name" {
  type        = string
  description = "Kubernetes group on the access entry when authorization is rbac"
  default     = "nullify-readonly"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$", var.kubernetes_group_name))
    error_message = "Lowercase letters, digits, '.' and '-' only (max 63 characters). ':' is not allowed, which excludes system: groups."
  }
}

variable "nullify_region" {
  type        = string
  description = "Your Nullify region, shown on the Nullify configure page. It selects the egress IPs the cluster's public endpoint must admit: ap-southeast-2, eu-central-1 or us-east-2"

  validation {
    condition     = contains(["ap-southeast-2", "eu-central-1", "us-east-2"], var.nullify_region)
    error_message = "nullify_region must be ap-southeast-2, eu-central-1 or us-east-2"
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the access entries"
  default     = {}
}

variable "collector_cluster_arns" {
  type        = list(string)
  description = "The subset of cluster_arns where a k8s-resources instance with enable_collector = true (or an equivalent manifest, or the nullify-k8s-collector Helm chart) already registers the cluster as an on-prem collector target. The module refuses to also create an access entry for one of these: the collector keys the cluster on cluster_name, this module's access entry keys the same cluster on its EKS ARN, and nothing joins the two, so the cluster would be listed twice in inventory with its pods and containers duplicated. Checked for every authorization mode, including admin_view_policy, which creates no Kubernetes objects and so is invisible to any precondition inside k8s-resources"
  default     = []
}
