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

  # KMS configuration. The key Nullify hands out lives in Nullify's account, so
  # key/* is granted next to the ARN: IAM never resolves an alias ARN in a
  # Resource, and the key policy on a key Nullify owns is the real gate on what
  # this role can use. The wildcard is derived only when the ARN's account
  # differs from this one, so a key pasted from the customer's own account
  # grants that key alone and reaches nothing else in the account. For a
  # Nullify-supplied key this grants what the CloudFormation template grants.
  enable_kms_access        = var.kms_key_arn != ""
  kms_arn_parts            = split(":", var.kms_key_arn)
  kms_arn_is_full          = length(local.kms_arn_parts) == 6
  kms_arn_account          = local.kms_arn_is_full ? element(local.kms_arn_parts, 4) : ""
  kms_arn_is_cross_account = local.kms_arn_is_full && local.kms_arn_account != data.aws_caller_identity.current.account_id
  kms_key_wildcard         = local.kms_arn_is_cross_account ? ["arn:${element(local.kms_arn_parts, 1)}:kms:${element(local.kms_arn_parts, 3)}:${local.kms_arn_account}:key/*"] : []
  kms_policy_resources     = local.enable_kms_access ? concat([var.kms_key_arn], local.kms_key_wildcard) : []

  # Common tags
  common_tags = merge(var.tags, {
    Customer = var.customer_name
  })
}
