# IAM Role for Nullify integration
resource "aws_iam_role" "nullify_readonly_role" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Policies
resource "aws_iam_policy" "readonly_policy_part1" {
  name        = local.readonly_policy_part1_name
  description = "Read-only access for AWS resources for Nullify (Part 1)"
  policy      = data.aws_iam_policy_document.readonly_policy_part1.json
  tags        = local.common_tags
}

resource "aws_iam_policy" "readonly_policy_part2" {
  name        = local.readonly_policy_part2_name
  description = "Read-only access for AWS resources for Nullify (Part 2)"
  policy      = data.aws_iam_policy_document.readonly_policy_part2.json
  tags        = local.common_tags
}

resource "aws_iam_policy" "s3_access_policy" {
  count = local.enable_s3_access ? 1 : 0
  
  name        = local.s3_access_policy_name
  description = "S3 access policy for Nullify bucket"
  policy      = data.aws_iam_policy_document.s3_access_policy[0].json
  tags        = local.common_tags
}

resource "aws_iam_policy" "deny_actions_policy" {
  name        = local.deny_actions_policy_name
  description = "Policy to explicitly deny certain actions"
  policy      = data.aws_iam_policy_document.deny_actions_policy.json
  tags        = local.common_tags
}

# Policy Attachments
resource "aws_iam_role_policy_attachment" "readonly_policy_part1" {
  role       = aws_iam_role.nullify_readonly_role.name
  policy_arn = aws_iam_policy.readonly_policy_part1.arn
}

resource "aws_iam_role_policy_attachment" "readonly_policy_part2" {
  role       = aws_iam_role.nullify_readonly_role.name
  policy_arn = aws_iam_policy.readonly_policy_part2.arn
}

resource "aws_iam_role_policy_attachment" "s3_access_policy" {
  count = local.enable_s3_access ? 1 : 0
  
  role       = aws_iam_role.nullify_readonly_role.name
  policy_arn = aws_iam_policy.s3_access_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "deny_actions_policy" {
  role       = aws_iam_role.nullify_readonly_role.name
  policy_arn = aws_iam_policy.deny_actions_policy.arn
} 