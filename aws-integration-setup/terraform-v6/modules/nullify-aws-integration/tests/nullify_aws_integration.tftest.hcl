mock_provider "aws" {
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

run "kms_alias_grants_the_alias_and_key_wildcard" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  assert {
    condition     = tolist(output.kms_policy_resources) == tolist(["arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads", "arn:aws:kms:eu-central-1:111122223333:key/*"])
    error_message = "An alias ARN must grant the alias and key/* in the same account and region"
  }
}

run "kms_multi_region_key_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  assert {
    condition     = contains(output.kms_policy_resources, "arn:aws:kms:us-east-2:111122223333:key/*")
    error_message = "A key ARN must also grant key/* in the same account and region"
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
