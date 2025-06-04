resource "kubernetes_namespace" "nullify" {
  metadata {
    name = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account" "nullify_collector_sa" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.nullify.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.iam_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "k8s-collector"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_cluster_role" "nullify_readonly_role" {
  metadata {
    name = "nullify-k8s-collector-role"
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources = [
      "pods",
      "services", 
      "endpoints",
      "namespaces",
      "nodes",
      "persistentvolumes",
      "persistentvolumeclaims",
      "serviceaccounts",
    ]
    verbs = ["get", "list"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "replicasets",
      "statefulsets",
      "daemonsets"
    ]
    verbs = ["get", "list"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources = [
      "roles",
      "rolebindings",
      "clusterroles",
      "clusterrolebindings"
    ]
    verbs = ["get", "list"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "nullify_collector_binding" {
  metadata {
    name = "nullify-k8s-collector-binding"
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.nullify_readonly_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.nullify_collector_sa.metadata[0].name
    namespace = kubernetes_namespace.nullify.metadata[0].name
  }
}

resource "kubernetes_cron_job_v1" "k8s_collector" {
  metadata {
    name      = "k8s-info-collector"
    namespace = kubernetes_namespace.nullify.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "nullify"
      "app.kubernetes.io/component" = "k8s-collector"
    }
  }

  spec {
    schedule                      = var.cronjob_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "nullify"
          "app.kubernetes.io/component" = "k8s-collector"
        }
      }

      spec {
        active_deadline_seconds = 21600

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"      = "nullify"
              "app.kubernetes.io/component" = "k8s-collector"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.nullify_collector_sa.metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "k8s-collector"
              image = var.collector_image

              env {
                name  = "NULLIFY_S3_BUCKET_NAME"
                value = var.s3_bucket_name
              }

              env {
                name  = "NULLIFY_S3_KEY_PREFIX"
                value = "k8s-collector"
              }

              env {
                name = "AWS_REGION"
                value = var.aws_region
              }

              resources {
                requests = {
                  memory = "256Mi"
                  cpu    = "100m"
                }
                limits = {
                  memory = "512Mi"
                  cpu    = "500m"
                }
              }
            }
          }
        }
      }
    }
  }
}
