output "role_arn" {
  description = "ARN of the IAM Role with cross-account read access"
  value       = module.nullify_aws_integration.role_arn
}

output "role_name" {
  description = "Name of the IAM Role created for Nullify"
  value       = module.nullify_aws_integration.role_name
}

output "external_id" {
  description = "External ID used for the IAM role"
  value       = module.nullify_aws_integration.external_id
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for scan results"
  value       = module.nullify_aws_integration.s3_bucket_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = module.nullify_aws_integration.aws_region
}

output "customer_name" {
  description = "Customer name used in resource naming"
  value       = module.nullify_aws_integration.customer_name
}

# Kubernetes-related outputs (only when enabled)
output "kubernetes_namespace" {
  description = "Name of the Kubernetes namespace for Nullify resources"
  value       = module.nullify_aws_integration.kubernetes_namespace
}

output "kubernetes_service_account" {
  description = "Name of the Kubernetes service account for the collector"
  value       = module.nullify_aws_integration.kubernetes_service_account
}

output "kubernetes_cluster_role" {
  description = "Name of the Kubernetes cluster role for the collector"
  value       = module.nullify_aws_integration.kubernetes_cluster_role
}

output "kubernetes_cronjob" {
  description = "Name of the Kubernetes CronJob for data collection"
  value       = module.nullify_aws_integration.kubernetes_cronjob
}

# Policy ARNs
output "policy_arns" {
  description = "ARNs of all IAM policies created"
  value       = module.nullify_aws_integration.policy_arns
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the Nullify integration deployment"
  value       = module.nullify_aws_integration.deployment_summary
} 