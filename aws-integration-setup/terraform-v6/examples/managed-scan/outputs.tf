output "role_arn" {
  description = "ARN of the Nullify read-only role"
  value       = module.nullify_aws_integration.role_arn
}

output "clusters_for_nullify" {
  description = "Clusters to register in Nullify"
  value       = module.eks_managed_scan_access.clusters_for_nullify
}

output "kubernetes_group_name" {
  description = "Kubernetes group the RBAC binding names"
  value       = module.eks_managed_scan_access.kubernetes_group_name
}

output "endpoint_allowlist" {
  description = "Whether Nullify's egress IPs can reach the cluster's public endpoint, and the command that adds any missing CIDRs"
  value       = module.eks_managed_scan_access.endpoint_allowlist
}
