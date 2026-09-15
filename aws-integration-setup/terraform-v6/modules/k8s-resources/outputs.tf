output "namespace_name" {
  description = "Name of the created Kubernetes namespace (null when enable_collector is false)"
  value       = one(kubernetes_namespace.nullify[*].metadata[0].name)
}

output "service_account_name" {
  description = "Name of the created Kubernetes service account (null when enable_collector is false)"
  value       = one(kubernetes_service_account.nullify_collector_sa[*].metadata[0].name)
}

output "cluster_role_name" {
  description = "Name of the collector's cluster role (null when enable_collector is false)"
  value       = one(kubernetes_cluster_role.nullify_readonly_role[*].metadata[0].name)
}

output "cluster_role_binding_name" {
  description = "Name of the collector's cluster role binding (null when enable_collector is false)"
  value       = one(kubernetes_cluster_role_binding.nullify_collector_binding[*].metadata[0].name)
}

output "cronjob_name" {
  description = "Name of the created CronJob (null when enable_collector is false)"
  value       = one(kubernetes_cron_job_v1.k8s_collector[*].metadata[0].name)
}

output "managed_scan_cluster_role_name" {
  description = "Name of the managed-scan ClusterRole (null when enable_managed_scan_rbac is false)"
  value       = one(kubernetes_cluster_role_v1.nullify_readonly[*].metadata[0].name)
}

output "managed_scan_cluster_role_binding_name" {
  description = "Name of the managed-scan ClusterRoleBinding (null when enable_managed_scan_rbac is false)"
  value       = one(kubernetes_cluster_role_binding_v1.nullify_readonly[*].metadata[0].name)
}

output "managed_scan_kubernetes_group" {
  description = "Kubernetes group bound to the managed-scan ClusterRole (null when enable_managed_scan_rbac is false)"
  value       = var.enable_managed_scan_rbac ? var.managed_scan_kubernetes_group : null
}
