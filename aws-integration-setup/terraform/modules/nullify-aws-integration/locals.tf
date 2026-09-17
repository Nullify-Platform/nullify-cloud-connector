locals {
  # Common naming
  role_name_prefix = "AWSIntegration-${var.customer_name}"
  role_name        = "${local.role_name_prefix}-NullifyReadOnlyRole"

  # Policy names
  readonly_policy_part1_name = "${local.role_name_prefix}-ReadOnlyAccess-Part1"
  readonly_policy_part2_name = "${local.role_name_prefix}-ReadOnlyAccess-Part2"
  s3_access_policy_name      = "${local.role_name_prefix}-S3Access"
  kms_access_policy_name     = "${local.role_name_prefix}-KMSAccess"
  deny_actions_policy_name   = "${local.role_name_prefix}-DenyActions"

  # Cross-account role ARN (use directly)
  nullify_role_arn = var.nullify_role_arn

  # OIDC subject for service account
  oidc_subject = "system:serviceaccount:${var.kubernetes_namespace}:${var.service_account_name}"

  # S3 configuration
  enable_s3_access = var.s3_bucket_name != "" || var.nullify_s3_access_point_arn != ""
  s3_bucket_arn    = var.s3_bucket_name != "" ? "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}" : ""

  # KMS configuration. IAM never resolves an alias ARN in a Resource, so
  # key/* is granted next to an alias ARN in that account and region. A
  # concrete key ARN grants that ARN only: it must not open every key in
  # Nullify's account. Nullify's key policy is the real gate on a key
  # Nullify owns.
  enable_kms_access    = var.kms_key_arn != ""
  kms_arn_parts        = split(":", var.kms_key_arn)
  kms_arn_is_full      = length(local.kms_arn_parts) == 6
  kms_arn_account      = local.kms_arn_is_full ? element(local.kms_arn_parts, 4) : ""
  kms_arn_is_alias     = local.kms_arn_is_full && strcontains(var.kms_key_arn, ":alias/")
  kms_key_wildcard     = local.kms_arn_is_alias ? ["arn:${element(local.kms_arn_parts, 1)}:kms:${element(local.kms_arn_parts, 3)}:${local.kms_arn_account}:key/*"] : []
  kms_policy_resources = local.enable_kms_access ? concat([var.kms_key_arn], local.kms_key_wildcard) : []

  # Common tags
  common_tags = merge(var.tags, {
    Customer = var.customer_name
  })
}
