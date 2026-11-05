mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_eks_cluster" {
    defaults = {
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
        }]
      }]
    }
  }
}

variables {
  customer_name    = "acme"
  external_id      = "external-id-123456"
  nullify_role_arn = "arn:aws:iam::123456789012:role/NullifyRole"
}

run "cross_account_alias_grants_the_alias_and_key_wildcard" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  assert {
    condition     = tolist(output.kms_policy_resources) == tolist(["arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads", "arn:aws:kms:eu-central-1:111122223333:key/*"])
    error_message = "An alias ARN in Nullify's account must grant the alias and key/* in that account and region"
  }
}

run "a_key_arn_grants_only_that_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  assert {
    condition     = tolist(output.kms_policy_resources) == tolist(["arn:aws:kms:us-east-2:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab"])
    error_message = "A concrete key ARN must grant that ARN only: key/* would open every key in Nullify's account"
  }
}

run "an_alias_in_this_account_still_grants_key_wildcard" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:alias/my-own-key"
  }

  assert {
    condition     = tolist(output.kms_policy_resources) == tolist(["arn:aws:kms:us-east-2:123456789012:alias/my-own-key", "arn:aws:kms:us-east-2:123456789012:key/*"])
    error_message = "An alias ARN must grant key/* because IAM does not resolve aliases"
  }
}

run "kms_is_optional" {
  command = plan

  assert {
    condition     = length(output.kms_policy_resources) == 0 && length(aws_iam_policy.kms_access_policy) == 0
    error_message = "No KMS policy without kms_key_arn"
  }
}

run "invalid_kms_arns_are_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:s3:::not-a-key"
  }

  expect_failures = [var.kms_key_arn]
}

run "s3_access_point_enables_the_s3_policy" {
  command = plan

  variables {
    nullify_s3_access_point_arn = "arn:aws:s3:eu-central-1:111122223333:accesspoint/acme-k8s-collector"
  }

  assert {
    condition     = length(aws_iam_policy.s3_access_policy) == 1
    error_message = "An access point alone must create the S3 policy"
  }
}

run "invalid_access_point_arns_are_rejected" {
  command = plan

  variables {
    nullify_s3_access_point_arn = "arn:aws:s3:::a-bucket"
  }

  expect_failures = [var.nullify_s3_access_point_arn]
}

run "clusters_are_read_in_their_own_region" {
  command = plan

  variables {
    enable_kubernetes_integration = true
    eks_cluster_arns              = ["arn:aws:eks:us-east-1:123456789012:cluster/prod"]
  }

  assert {
    condition     = data.aws_eks_cluster.clusters[0].region == "us-east-1"
    error_message = "Each cluster must be read in the region from its ARN"
  }

  assert {
    condition     = output.all_oidc_ids[0] == "EXAMPLED539D4633E53DE1B716D3041E"
    error_message = "The OIDC ID must come from the cluster's issuer"
  }
}

run "kubernetes_integration_needs_clusters" {
  command = plan

  variables {
    enable_kubernetes_integration = true
  }

  expect_failures = [data.aws_iam_policy_document.assume_role_policy]
}

# The mock above fakes every aws_iam_policy_document's computed `json`, so a
# passing test only proves the module plans, not that a policy grants any
# action. `statement` blocks are the data source's own configuration -- they
# are plan-time known even when the resulting document is mocked -- so assert
# on those instead.
run "kms_policy_grants_the_expected_actions_and_resources" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  assert {
    condition = toset(data.aws_iam_policy_document.kms_access_policy[0].statement[0].actions) == toset([
      "kms:DescribeKey",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ])
    error_message = "The KMS policy must grant exactly these actions, no more and no less"
  }

  assert {
    condition     = tolist(data.aws_iam_policy_document.kms_access_policy[0].statement[0].resources) == tolist(output.kms_policy_resources)
    error_message = "The KMS policy statement's resources must be exactly the derived kms_policy_resources output"
  }
}

run "s3_access_point_policy_grants_put_only_under_the_collector_prefix" {
  command = plan

  variables {
    nullify_s3_access_point_arn = "arn:aws:s3:eu-central-1:111122223333:accesspoint/nullify-uploads"
  }

  assert {
    condition = toset(data.aws_iam_policy_document.s3_access_policy[0].statement[0].actions) == toset([
      "s3:PutObject",
      "s3:PutObjectAcl",
    ])
    error_message = "The access point statement must grant only PutObject and PutObjectAcl"
  }

  assert {
    condition     = tolist(data.aws_iam_policy_document.s3_access_policy[0].statement[0].resources) == tolist(["arn:aws:s3:eu-central-1:111122223333:accesspoint/nullify-uploads/object/k8s-collector/*"])
    error_message = "The access point statement must be scoped to the k8s-collector object prefix, not the whole access point"
  }
}

run "readonly_policy_grants_a_read_only_action" {
  command = plan

  assert {
    condition     = contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "access-analyzer:List*")
    error_message = "The readonly policy's first statement must contain the expected access-analyzer read action"
  }

  assert {
    condition     = data.aws_iam_policy_document.readonly_policy_part1.statement[0].effect == "Allow"
    error_message = "The readonly policy statement must Allow, not Deny"
  }
}

run "permission_bar_scopes_secret_shaped_reads" {
  command = plan

  assert {
    condition     = !contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "ec2:DescribeLaunchTemplateVersions") && contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "ec2:DescribeLaunchTemplates")
    error_message = "DescribeLaunchTemplateVersions returns UserData in the clear and must not be allowed; DescribeLaunchTemplates stays"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "ecr:GetDownloadUrlForLayer") && contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "ecr:BatchGetImage") && contains(data.aws_iam_policy_document.readonly_policy_part1.statement[0].actions, "ecr:GetAuthorizationToken")
    error_message = "Image pull and ECR auth must be allowed so scanning can fetch customer images"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.readonly_policy_part2.statement[0].actions, "lambda:GetFunction") && !contains(data.aws_iam_policy_document.readonly_policy_part2.statement[0].actions, "ssm:GetDocument")
    error_message = "lambda:GetFunction stays on *; ssm:GetDocument must leave the wildcard allow"
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.readonly_policy_part2.statement : s if toset(s.actions) == toset(["ssm:GetDocument"]) && toset(s.resources) == toset(["arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell"])]) == 1
    error_message = "ssm:GetDocument must be allowed only on SSM-SessionManagerRunShell in this partition"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "ec2:DescribeLaunchTemplateVersions") && contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "events:ListTargetsByRule")
    error_message = "UserData and EventBridge target Input must be denied"
  }

  assert {
    condition     = !contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "ecr:GetDownloadUrlForLayer") && !contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "ecr:BatchGetImage") && !contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "ecr:GetAuthorizationToken") && !contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "lambda:GetFunction") && !contains(data.aws_iam_policy_document.deny_actions_policy.statement[0].actions, "ssm:GetDocument")
    error_message = "Image pull, lambda:GetFunction and scoped GetDocument must not be denied"
  }
}
