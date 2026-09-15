mock_provider "aws" {
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
    condition     = aws_eks_access_entry.nullify["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].region == "eu-west-1"
    error_message = "The access entry must be created in the cluster's own region"
  }

  assert {
    condition     = toset(aws_eks_access_entry.nullify["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].kubernetes_groups) == toset(["nullify-readonly"])
    error_message = "rbac mode must put the entry in the nullify-readonly group"
  }

  assert {
    condition     = length(aws_eks_access_policy_association.admin_view) == 0
    error_message = "rbac mode must not associate any access policy"
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

run "admin_view_policy_is_cluster_scoped_and_warns" {
  command = plan

  variables {
    authorization = "admin_view_policy"
  }

  expect_failures = [check.admin_view_policy_is_broader_than_required]

  assert {
    condition     = aws_eks_access_policy_association.admin_view["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
    error_message = "admin_view_policy must associate AmazonEKSAdminViewPolicy"
  }

  assert {
    condition     = aws_eks_access_policy_association.admin_view["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].access_scope[0].type == "cluster"
    error_message = "The access policy must be cluster scoped"
  }

  assert {
    condition     = output.kubernetes_group_name == null
    error_message = "admin_view_policy binds no Kubernetes group"
  }

  assert {
    condition     = length(aws_eks_access_entry.nullify["arn:aws:eks:eu-west-1:123456789012:cluster/prod"].kubernetes_groups) == 0
    error_message = "admin_view_policy must plan kubernetes_groups as an empty set on the entry: the attribute is Optional+Computed, so null would keep whatever is in state. This pins the planned configuration under a mocked provider, not the applied result"
  }
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

run "a_collector_cluster_is_rejected_even_under_admin_view_policy" {
  # admin_view_policy creates no Kubernetes objects, so the k8s-resources
  # ClusterRole's own precondition can never see this combination. The guard
  # has to live here, on the access entry every authorization mode creates.
  command = plan

  variables {
    authorization          = "admin_view_policy"
    collector_cluster_arns = ["arn:aws:eks:eu-west-1:123456789012:cluster/prod"]
  }

  expect_failures = [data.aws_eks_cluster.this, check.admin_view_policy_is_broader_than_required]
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
  # The guard compares full ARNs, not bare cluster names. This tree supports
  # collector_cluster_arns spanning multiple regions in one instance (see the
  # README's multi-region example), so a cluster called "prod" in eu-west-1
  # (cluster_arns) must not collide with an unrelated cluster also called
  # "prod" in us-east-1 (collector_cluster_arns).
  command = plan

  variables {
    collector_cluster_arns = ["arn:aws:eks:us-east-1:123456789012:cluster/prod"]
  }

  assert {
    condition     = length(aws_eks_access_entry.nullify) == 1
    error_message = "A same-named cluster in a different region must not be mistaken for the same cluster"
  }
}
