moved {
  from = kubernetes_namespace.nullify
  to   = kubernetes_namespace.nullify[0]
}

moved {
  from = kubernetes_service_account.nullify_collector_sa
  to   = kubernetes_service_account.nullify_collector_sa[0]
}

moved {
  from = kubernetes_cluster_role.nullify_readonly_role
  to   = kubernetes_cluster_role.nullify_readonly_role[0]
}

moved {
  from = kubernetes_cluster_role_binding.nullify_collector_binding
  to   = kubernetes_cluster_role_binding.nullify_collector_binding[0]
}

moved {
  from = kubernetes_cron_job_v1.k8s_collector
  to   = kubernetes_cron_job_v1.k8s_collector[0]
}
