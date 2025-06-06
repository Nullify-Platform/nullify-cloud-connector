output "role_arn" {
  description = "ARN of the IAM Role with cross-account read access"
  value       = aws_iam_role.nullify_readonly_role.arn
}

output "role_name" {
  description = "Name of the IAM Role created for Nullify"
  value       = aws_iam_role.nullify_readonly_role.name
}

output "external_id" {
  description = "External ID used for the IAM role"
  value       = var.external_id
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for scan results (null if S3 not configured)"
  value       = var.s3_bucket_name != "" ? var.s3_bucket_name : null
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "customer_name" {
  description = "Customer name used in resource naming"
  value       = var.customer_name
}

# EKS/OIDC related outputs
output "all_oidc_ids" {
  description = "List of all OIDC provider IDs for integrated clusters"
  value       = var.enable_kubernetes_integration ? local.all_oidc_ids : null
}

output "all_oidc_provider_arns" {
  description = "List of ARNs of all EKS OIDC providers used for the integration"
  value       = var.enable_kubernetes_integration ? local.eks_oidc_provider_arns : null
}

output "cluster_integration_summary" {
  description = "Summary of all cluster integrations"
  value = var.enable_kubernetes_integration ? {
    total_clusters = length(local.all_clusters_info)
    clusters = [
      for cluster in local.all_clusters_info : {
        region  = cluster.region
        oidc_id = cluster.oidc_id
      }
    ]
  } : null
}

output "all_clusters_info" {
  description = "Complete information about all integrated clusters including regions"
  value = var.enable_kubernetes_integration ? [
    for cluster in local.all_clusters_info : {
      region  = cluster.region
      oidc_id = cluster.oidc_id
    }
  ] : null
}

# Policy ARNs
output "policy_arns" {
  description = "ARNs of all IAM policies created"
  value = {
    readonly_part1 = aws_iam_policy.readonly_policy_part1.arn
    readonly_part2 = aws_iam_policy.readonly_policy_part2.arn
    s3_access      = local.enable_s3_access ? aws_iam_policy.s3_access_policy[0].arn : null
    deny_actions   = aws_iam_policy.deny_actions_policy.arn
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the Nullify integration deployment"
  value = {
    role_arn                   = aws_iam_role.nullify_readonly_role.arn
    customer_name              = var.customer_name
    aws_region                 = var.aws_region
    s3_bucket                  = var.s3_bucket_name != "" ? var.s3_bucket_name : null
    s3_integration_enabled     = local.enable_s3_access
    kubernetes_integration     = var.enable_kubernetes_integration
    total_clusters_configured  = var.enable_kubernetes_integration ? length(local.all_oidc_ids) : 0
  }
} 