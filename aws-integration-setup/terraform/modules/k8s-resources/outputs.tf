output "namespace_name" {
  description = "Name of the created Kubernetes namespace"
  value       = kubernetes_namespace.nullify.metadata[0].name
}

output "service_account_name" {
  description = "Name of the created Kubernetes service account"
  value       = kubernetes_service_account.nullify_collector_sa.metadata[0].name
}

output "cluster_role_name" {
  description = "Name of the created cluster role"
  value       = kubernetes_cluster_role.nullify_readonly_role.metadata[0].name
}

output "cluster_role_binding_name" {
  description = "Name of the created cluster role binding"
  value       = kubernetes_cluster_role_binding.nullify_collector_binding.metadata[0].name
}

output "cronjob_name" {
  description = "Name of the created CronJob"
  value       = kubernetes_cron_job_v1.k8s_collector.metadata[0].name
}
