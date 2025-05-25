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

# Kubernetes-related outputs (only when enabled)
output "kubernetes_namespace" {
  description = "Name of the Kubernetes namespace for Nullify resources"
  value       = var.enable_kubernetes_integration ? kubernetes_namespace.nullify[0].metadata[0].name : null
}

output "kubernetes_service_account" {
  description = "Name of the Kubernetes service account for the collector"
  value       = var.enable_kubernetes_integration ? kubernetes_service_account.nullify_collector_sa[0].metadata[0].name : null
}

output "kubernetes_cluster_role" {
  description = "Name of the Kubernetes cluster role for the collector"
  value       = var.enable_kubernetes_integration ? kubernetes_cluster_role.nullify_readonly_role[0].metadata[0].name : null
}

output "kubernetes_cronjob" {
  description = "Name of the Kubernetes CronJob for data collection"
  value       = var.enable_kubernetes_integration ? kubernetes_cron_job_v1.k8s_collector[0].metadata[0].name : null
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
    kubernetes_namespace       = var.enable_kubernetes_integration ? kubernetes_namespace.nullify[0].metadata[0].name : null
    kubernetes_service_account = var.enable_kubernetes_integration ? kubernetes_service_account.nullify_collector_sa[0].metadata[0].name : null
    cronjob_schedule           = var.cronjob_schedule
  }
} 