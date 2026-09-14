output "access_entry_arns" {
  description = "Access entry ARN per cluster ARN"
  value       = { for key, entry in aws_eks_access_entry.nullify : key => entry.access_entry_arn }
}

output "authorization" {
  description = "How Kubernetes authorizes Nullify: rbac or admin_view_policy"
  value       = var.authorization
}

output "kubernetes_group_name" {
  description = "Group the RBAC binding must name (null for admin_view_policy)"
  value       = var.authorization == "rbac" ? var.kubernetes_group_name : null
}

output "nullify_egress_cidrs" {
  description = "Nullify egress CIDRs for nullify_region that each cluster's public endpoint must admit"
  value       = local.nullify_egress_cidrs
}

output "clusters_for_nullify" {
  description = "Clusters to register in Nullify"
  value = [
    for key, cluster in local.clusters : {
      arn    = key
      name   = cluster.name
      region = cluster.region
    }
  ]
}

output "endpoint_allowlist" {
  description = "Per cluster: whether Nullify's egress IPs can reach the public endpoint, the CIDRs to add, and an AWS CLI command that adds them to the existing list. This module never changes publicAccessCidrs"
  value = {
    for key, endpoint in local.endpoints : key => {
      public_endpoint_enabled = endpoint.public_access
      missing_cidrs           = endpoint.missing_cidrs
      update_command          = endpoint.public_access && length(endpoint.missing_cidrs) > 0 ? format("aws eks update-cluster-config --region %s --name %s --resources-vpc-config '%s'", local.clusters[key].region, local.clusters[key].name, jsonencode({ publicAccessCidrs = concat(endpoint.cidrs, endpoint.missing_cidrs) })) : null
    }
  }
}
