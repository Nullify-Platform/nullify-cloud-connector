locals {
  # These are the NAT gateway Elastic IPs Nullify's scan compute egresses
  # through in each region, sourced from the platform monorepo's
  # `iac/network/vpc` module (`aws_eip.nat`, imported per prod workspace in
  # `imports.tf`) -- not allocated or owned by this repo. They change only if
  # Nullify recreates a NAT gateway; if a cluster starts failing the
  # `nullify_endpoint_allowlist` check with no config change on your side,
  # re-fetch this list rather than assuming a local misconfiguration.
  nullify_egress_cidrs_by_region = {
    "ap-southeast-2" = ["13.55.32.104/32", "3.105.146.106/32", "13.211.99.100/32"]
    "eu-central-1"   = ["18.198.60.231/32", "18.157.227.250/32", "18.185.152.197/32"]
    "us-east-2"      = ["52.15.146.50/32", "16.58.40.80/32", "3.133.15.210/32"]
  }

  nullify_egress_cidrs = local.nullify_egress_cidrs_by_region[var.nullify_region]
  principal_account    = split(":", var.principal_arn)[4]

  clusters = {
    for arn in var.cluster_arns : arn => {
      name      = split("/", arn)[1]
      partition = split(":", arn)[1]
      region    = split(":", arn)[3]
      account   = split(":", arn)[4]
    }
  }

  collector_cluster_arns = toset(var.collector_cluster_arns)
}

data "aws_region" "current" {}

data "aws_eks_cluster" "this" {
  for_each = local.clusters

  name = each.value.name

  lifecycle {
    precondition {
      condition     = each.value.region == data.aws_region.current.name
      error_message = "Cluster ${each.key} is in ${each.value.region}, but this module's AWS provider is in ${data.aws_region.current.name}. AWS provider v5 manages access entries only in the provider's region: instantiate this module once per region with providers = { aws = aws.<region> }, or use terraform-v6."
    }

    precondition {
      condition     = each.value.account == local.principal_account
      error_message = "Cluster ${each.key} is in account ${each.value.account}, but principal_arn is in account ${local.principal_account}. Nullify assumes the integration role in the cluster's own account: deploy nullify-aws-integration there and pass that role."
    }

    precondition {
      condition     = !contains(local.collector_cluster_arns, each.key)
      error_message = "Cluster ${each.value.name} (${each.key}) is also in collector_cluster_arns. The collector's upload registers it as an on-prem cluster keyed on cluster_name; this module's access entry registers the same cluster as its EKS ARN. Nothing joins the two, so the cluster would be listed twice in inventory with its pods and containers duplicated. Pick one mode per cluster: drop its ARN from collector_cluster_arns and cluster_arns here, or stop treating it as a collector target (disable enable_collector on its k8s-resources instance, or remove it from the Helm chart or manifest that registers it)."
    }
  }
}

resource "terraform_data" "principal_identity" {
  input = var.principal_unique_id
}

resource "aws_eks_access_entry" "nullify" {
  for_each = local.clusters

  cluster_name      = data.aws_eks_cluster.this[each.key].name
  principal_arn     = var.principal_arn
  type              = "STANDARD"
  kubernetes_groups = [var.kubernetes_group_name]
  tags              = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.principal_identity]

    precondition {
      condition     = contains(["API", "API_AND_CONFIG_MAP"], try(data.aws_eks_cluster.this[each.key].access_config[0].authentication_mode, "CONFIG_MAP"))
      error_message = "Cluster ${each.value.name} (${each.value.region}) uses authentication mode CONFIG_MAP, which does not support access entries. Switch it (one-way) with: aws eks update-cluster-config --region ${each.value.region} --name ${each.value.name} --access-config authenticationMode=API_AND_CONFIG_MAP. Or remove it from cluster_arns and map the role in aws-auth instead (see README)."
    }
  }
}

locals {
  endpoints = {
    for key, cluster in data.aws_eks_cluster.this : key => {
      public_access = cluster.vpc_config[0].endpoint_public_access
      cidrs         = tolist(cluster.vpc_config[0].public_access_cidrs)
      missing_cidrs = [for cidr in local.nullify_egress_cidrs : cidr if !contains(cluster.vpc_config[0].public_access_cidrs, cidr) && !contains(cluster.vpc_config[0].public_access_cidrs, "0.0.0.0/0")]
    }
  }

  unreachable_clusters = [for key, endpoint in local.endpoints : key if !endpoint.public_access || length(endpoint.missing_cidrs) > 0]
}

check "nullify_can_reach_cluster_endpoints" {
  assert {
    condition     = length(local.unreachable_clusters) == 0
    error_message = "Nullify's ${var.nullify_region} egress IPs cannot reach the public endpoint of: ${join(", ", local.unreachable_clusters)}. This module does not change publicAccessCidrs; see the endpoint_allowlist output for the missing CIDRs and an update command. The check matches exact CIDRs, so a wider range that already covers Nullify's IPs also warns."
  }
}
