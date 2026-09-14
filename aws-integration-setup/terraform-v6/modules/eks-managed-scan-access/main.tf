locals {
  nullify_egress_cidrs_by_region = {
    "ap-southeast-2" = ["13.55.32.104/32", "3.105.146.106/32", "13.211.99.100/32"]
    "eu-central-1"   = ["18.198.60.231/32", "18.157.227.250/32", "18.185.152.197/32"]
    "us-east-2"      = ["52.15.146.50/32", "16.58.40.80/32", "3.133.15.210/32"]
  }

  nullify_egress_cidrs = local.nullify_egress_cidrs_by_region[var.nullify_region]
  principal_account    = split(":", var.principal_arn)[4]

  clusters = {
    for arn in var.cluster_arns : arn => {
      name    = split("/", arn)[1]
      region  = split(":", arn)[3]
      account = split(":", arn)[4]
    }
  }
}

data "aws_eks_cluster" "this" {
  for_each = local.clusters

  region = each.value.region
  name   = each.value.name

  lifecycle {
    precondition {
      condition     = each.value.account == local.principal_account
      error_message = "Cluster ${each.key} is in account ${each.value.account}, but principal_arn is in account ${local.principal_account}. Nullify assumes the integration role in the cluster's own account: deploy nullify-aws-integration there and pass that role."
    }
  }
}

resource "terraform_data" "principal_identity" {
  input = var.principal_unique_id
}

resource "aws_eks_access_entry" "nullify" {
  for_each = local.clusters

  region            = each.value.region
  cluster_name      = data.aws_eks_cluster.this[each.key].name
  principal_arn     = var.principal_arn
  type              = "STANDARD"
  kubernetes_groups = var.authorization == "rbac" ? [var.kubernetes_group_name] : []
  tags              = var.tags

  lifecycle {
    replace_triggered_by = [terraform_data.principal_identity]

    precondition {
      condition     = contains(["API", "API_AND_CONFIG_MAP"], try(data.aws_eks_cluster.this[each.key].access_config[0].authentication_mode, "CONFIG_MAP"))
      error_message = "Cluster ${each.value.name} (${each.value.region}) uses authentication mode CONFIG_MAP, which does not support access entries. Switch it (one-way) with: aws eks update-cluster-config --region ${each.value.region} --name ${each.value.name} --access-config authenticationMode=API_AND_CONFIG_MAP. Or remove it from cluster_arns and map the role in aws-auth instead (see README)."
    }
  }
}

resource "aws_eks_access_policy_association" "admin_view" {
  for_each = { for key, cluster in local.clusters : key => cluster if var.authorization == "admin_view_policy" }

  region        = each.value.region
  cluster_name  = aws_eks_access_entry.nullify[each.key].cluster_name
  principal_arn = aws_eks_access_entry.nullify[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  lifecycle {
    replace_triggered_by = [aws_eks_access_entry.nullify[each.key].access_entry_arn]
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

check "admin_view_policy_is_broader_than_required" {
  assert {
    condition     = var.authorization != "admin_view_policy"
    error_message = "authorization = admin_view_policy associates AmazonEKSAdminViewPolicy: get, list and watch on every resource, including Secrets, custom resources and pods/log. On EKS 1.34 and earlier get pods/exec is enough to exec into pods, and these grants do not show in kubectl auth can-i --list. The default rbac mode grants list on only the kinds Nullify reads."
  }
}
