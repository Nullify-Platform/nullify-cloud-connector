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
  s3_bucket_arn    = var.s3_bucket_name != "" ? "arn:aws:s3:::${var.s3_bucket_name}" : ""

  # KMS configuration. IAM ignores alias ARNs in Resource, so key/* in the same
  # account and region is granted too; Nullify's key policy is the real gate.
  enable_kms_access = var.kms_key_arn != ""
  kms_arn_parts     = split(":", var.kms_key_arn)

  kms_policy_resources = local.enable_kms_access ? [
    var.kms_key_arn,
    "arn:aws:kms:${element(local.kms_arn_parts, 3)}:${element(local.kms_arn_parts, 4)}:key/*",
  ] : []

  # Common tags
  common_tags = merge(var.tags, {
    Customer = var.customer_name
  })
}
