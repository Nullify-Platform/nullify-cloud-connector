# AWS Integration Outputs
output "iam_role_arn" {
  description = "ARN of the IAM Role with cross-account read access"
  value       = module.nullify_aws_integration.role_arn
}

output "deployment_summary" {
  description = "Summary of the complete Nullify integration deployment"
  value       = module.nullify_aws_integration.deployment_summary
}

output "cluster_integration_summary" {
  description = "Summary of all cluster integrations"
  value       = module.nullify_aws_integration.cluster_integration_summary
}

# Kubernetes Resources
output "k8s_resources_primary" {
  description = "Kubernetes resources deployed to primary cluster"
  value = {
    namespace_name                 = module.k8s_resources_primary.namespace_name
    service_account_name           = module.k8s_resources_primary.service_account_name
    cluster_role_name              = module.k8s_resources_primary.cluster_role_name
    cluster_role_binding_name      = module.k8s_resources_primary.cluster_role_binding_name
    cronjob_name                   = module.k8s_resources_primary.cronjob_name
    managed_scan_cluster_role_name = module.k8s_resources_primary.managed_scan_cluster_role_name
  }
}

output "k8s_resources_secondary" {
  description = "Kubernetes resources deployed to secondary cluster"
  value = {
    namespace_name                 = module.k8s_resources_secondary.namespace_name
    service_account_name           = module.k8s_resources_secondary.service_account_name
    cluster_role_name              = module.k8s_resources_secondary.cluster_role_name
    cluster_role_binding_name      = module.k8s_resources_secondary.cluster_role_binding_name
    cronjob_name                   = module.k8s_resources_secondary.cronjob_name
    managed_scan_cluster_role_name = module.k8s_resources_secondary.managed_scan_cluster_role_name
  }
}

# Managed EKS scan (empty unless scan_mode is managed or both)
output "managed_scan_clusters_for_nullify" {
  description = "Clusters to register in Nullify for the managed scan"
  value       = flatten(concat(module.eks_managed_scan_access_primary[*].clusters_for_nullify, module.eks_managed_scan_access_secondary[*].clusters_for_nullify))
}

output "managed_scan_endpoint_allowlist" {
  description = "Per cluster: whether Nullify's egress IPs can reach the public endpoint, and a command that adds any missing CIDRs"
  value       = merge(concat(module.eks_managed_scan_access_primary[*].endpoint_allowlist, module.eks_managed_scan_access_secondary[*].endpoint_allowlist)...)
}
