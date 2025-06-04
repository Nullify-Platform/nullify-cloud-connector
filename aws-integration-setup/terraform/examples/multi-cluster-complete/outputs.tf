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

# Cluster A Kubernetes Resources
output "k8s_resources" {
  description = "Kubernetes resources deployed to primary cluster"
  value = {
    namespace_name           = module.k8s_resources.namespace_name
    service_account_name     = module.k8s_resources.service_account_name
    cluster_role_name        = module.k8s_resources.cluster_role_name
    cluster_role_binding_name = module.k8s_resources.cluster_role_binding_name
    cronjob_name            = module.k8s_resources.cronjob_name
  }
}
