mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }

  mock_data "aws_eks_cluster" {
    defaults = {
      access_config = [{
        authentication_mode = "API_AND_CONFIG_MAP"
      }]
      vpc_config = [{
        endpoint_public_access = true
        public_access_cidrs    = ["0.0.0.0/0"]
      }]
    }
  }
}

mock_provider "aws" {
  alias = "config_map"

  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }

  mock_data "aws_eks_cluster" {
    defaults = {
      access_config = [{
        authentication_mode = "CONFIG_MAP"
      }]
      vpc_config = [{
        endpoint_public_access = true
        public_access_cidrs    = ["0.0.0.0/0"]
      }]
    }
  }
}

mock_provider "aws" {
  alias = "restricted_endpoint"

  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }

  mock_data "aws_eks_cluster" {
    defaults = {
      access_config = [{
        authentication_mode = "API"
      }]
      vpc_config = [{
        endpoint_public_access = true
        public_access_cidrs    = ["10.0.0.0/8", "18.198.60.231/32"]
      }]
    }
  }
}

mock_provider "aws" {
  alias = "private_endpoint"

  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }

  mock_data "aws_eks_cluster" {
    defaults = {
      access_config = [{
        authentication_mode = "API"
      }]
      vpc_config = [{
        endpoint_public_access = false
        public_access_cidrs    = ["0.0.0.0/0"]
      }]
    }
  }
}

variables {
  principal_arn       = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
  principal_unique_id = "AROAEXAMPLEUNIQUEID01"
  nullify_region      = "eu-central-1"
  cluster_arns        = ["arn:aws:eks:eu-west-1:123456789012:cluster/prod"]
}

run "rbac_is_the_default" {
  assert {
    condition     = length(aws_eks_access_entry.nullify) == 1
    error_message = "Expected one access entry per cluster"
  }

  assert {
    condition     = toset(aws_eks_access_entry.nullify["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].kubernetes_groups) == toset(["nullify-readonly"])
    error_message = "rbac mode must put the entry in the nullify-readonly group"
  }

  assert {
    condition     = output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].update_command == null
    error_message = "An endpoint open to 0.0.0.0/0 needs no update"
  }

  assert {
    condition     = output.kubernetes_group_name == "nullify-readonly"
    error_message = "kubernetes_group_name output must name the bound group"
  }
}

run "clusters_outside_the_provider_region_are_rejected" {
  command = plan

  variables {
    cluster_arns = ["arn:aws:eks:us-east-1:123456789012:cluster/prod"]
  }

  expect_failures = [data.aws_eks_cluster.this]
}

run "config_map_clusters_are_rejected" {
  command = plan

  providers = {
    aws = aws.config_map
  }

  expect_failures = [aws_eks_access_entry.nullify]
}

run "restricted_endpoint_warns_and_prints_the_missing_cidrs" {
  command = plan

  providers = {
    aws = aws.restricted_endpoint
  }

  expect_failures = [check.nullify_can_reach_cluster_endpoints]

  assert {
    condition     = length(output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].missing_cidrs) == 2
    error_message = "Only the two absent eu-central-1 CIDRs should be missing"
  }

  assert {
    condition     = !contains(output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].missing_cidrs, "18.198.60.231/32")
    error_message = "A CIDR already in publicAccessCidrs must not be reported missing"
  }

  assert {
    condition     = strcontains(output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].update_command, "10.0.0.0/8") && strcontains(output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].update_command, "18.185.152.197/32")
    error_message = "The update command must keep existing CIDRs and add the missing ones"
  }
}

run "private_endpoint_warns_without_a_command" {
  command = plan

  providers = {
    aws = aws.private_endpoint
  }

  expect_failures = [check.nullify_can_reach_cluster_endpoints]

  assert {
    condition     = output.endpoint_allowlist["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].update_command == null
    error_message = "No publicAccessCidrs command applies while the public endpoint is disabled"
  }
}

run "admin_view_policy_is_rejected" {
  command = plan

  variables {
    authorization = "admin_view_policy"
  }

  expect_failures = [var.authorization]
}

run "view_policy_is_not_offered" {
  command = plan

  variables {
    authorization = "AmazonEKSViewPolicy"
  }

  expect_failures = [var.authorization]
}

run "system_groups_are_rejected" {
  command = plan

  variables {
    kubernetes_group_name = "system:masters"
  }

  expect_failures = [var.kubernetes_group_name]
}

run "cross_account_clusters_are_rejected" {
  command = plan

  variables {
    cluster_arns = ["arn:aws:eks:eu-west-1:999999999999:cluster/prod"]
  }

  expect_failures = [data.aws_eks_cluster.this]
}

run "a_collector_cluster_is_rejected" {
  command = plan

  variables {
    collector_cluster_arns = ["arn:aws:eks:eu-west-1:123456789012:cluster/prod"]
  }

  expect_failures = [data.aws_eks_cluster.this]
}

run "a_cluster_not_in_collector_cluster_arns_is_unaffected" {
  command = plan

  variables {
    collector_cluster_arns = ["arn:aws:eks:eu-west-1:123456789012:cluster/some-other-cluster"]
  }

  assert {
    condition     = length(aws_eks_access_entry.nullify) == 1
    error_message = "A collector_cluster_arns entry for a different cluster must not block this one"
  }
}

run "a_same_named_cluster_in_another_region_is_unaffected" {
  # The guard compares full ARNs, not bare cluster names: cluster_arns names
  # a cluster called "prod" in eu-west-1, and this collector_cluster_arns
  # entry names a different cluster that happens to share the name "prod" in
  # us-east-1. Comparing names alone would collide the two and reject the
  # entry, even though nothing is duplicated.
  command = plan

  variables {
    collector_cluster_arns = ["arn:aws:eks:us-east-1:123456789012:cluster/prod"]
  }

  assert {
    condition     = length(aws_eks_access_entry.nullify) == 1
    error_message = "A same-named cluster in a different region must not be mistaken for the same cluster"
  }
}
