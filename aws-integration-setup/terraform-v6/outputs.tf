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
output "cluster_integration_summary" {
  description = "Summary of all cluster integrations"
  value       = module.nullify_aws_integration.cluster_integration_summary
}

output "all_clusters_info" {
  description = "Complete information about all integrated clusters"
  value       = module.nullify_aws_integration.all_clusters_info
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

output "managed_scan_clusters_for_nullify" {
  description = "Clusters to register in Nullify for the managed scan (null when enable_managed_scan is false)"
  value       = one(module.eks_managed_scan_access[*].clusters_for_nullify)
}

output "managed_scan_kubernetes_group" {
  description = "Kubernetes group to bind to the nullify-readonly ClusterRole (null when disabled)"
  value       = one(module.eks_managed_scan_access[*].kubernetes_group_name)
}

output "managed_scan_endpoint_allowlist" {
  description = "Per cluster: whether Nullify's egress IPs can reach the public endpoint, and a command that adds any missing CIDRs"
  value       = one(module.eks_managed_scan_access[*].endpoint_allowlist)
}

output "nullify_egress_cidrs" {
  description = "Nullify egress CIDRs for nullify_region (null when enable_managed_scan is false)"
  value       = one(module.eks_managed_scan_access[*].nullify_egress_cidrs)
}
