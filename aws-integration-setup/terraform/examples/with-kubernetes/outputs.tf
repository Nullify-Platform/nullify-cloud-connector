output "role_arn" {
  description = "ARN of the IAM Role with cross-account read access"
  value       = module.nullify_aws_integration.role_arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster being integrated"
  value       = var.eks_cluster_name
}

output "kubernetes_namespace" {
  description = "Name of the Kubernetes namespace for Nullify resources"
  value       = module.nullify_aws_integration.kubernetes_namespace
}

output "kubernetes_service_account" {
  description = "Name of the Kubernetes service account for the collector"
  value       = module.nullify_aws_integration.kubernetes_service_account
}

output "kubernetes_cronjob" {
  description = "Name of the Kubernetes CronJob for data collection"
  value       = module.nullify_aws_integration.kubernetes_cronjob
}

output "deployment_summary" {
  description = "Summary of the Nullify integration deployment"
  value       = module.nullify_aws_integration.deployment_summary
}

output "oidc_provider_id" {
  description = "The OIDC provider ID extracted from the EKS cluster"
  value       = local.oidc_provider_id
} 