locals {
  # Common naming
  role_name_prefix = "AWSIntegration-${var.customer_name}"
  role_name        = "${local.role_name_prefix}-NullifyReadOnlyRole"
  
  # Policy names
  readonly_policy_part1_name = "${local.role_name_prefix}-ReadOnlyAccess-Part1"
  readonly_policy_part2_name = "${local.role_name_prefix}-ReadOnlyAccess-Part2"
  s3_access_policy_name      = "${local.role_name_prefix}-S3Access"
  deny_actions_policy_name   = "${local.role_name_prefix}-DenyActions"
  
  # Cross-account role ARN (use directly)
  nullify_role_arn = var.nullify_role_arn
  
  # EKS OIDC provider ARN
  eks_oidc_provider_arn = var.enable_kubernetes_integration ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/${var.eks_oidc_id}" : ""
  
  # OIDC subject for service account
  oidc_subject = "system:serviceaccount:${var.kubernetes_namespace}:${var.service_account_name}"
  
  # S3 configuration
  enable_s3_access = var.s3_bucket_name != ""
  s3_bucket_arn    = var.s3_bucket_name != "" ? "arn:aws:s3:::${var.s3_bucket_name}" : ""
  
  # Kubernetes resources flag
  create_kubernetes_resources = var.enable_kubernetes_integration
  
  # Common tags
  common_tags = merge(var.tags, {
    Customer = var.customer_name
  })
} 