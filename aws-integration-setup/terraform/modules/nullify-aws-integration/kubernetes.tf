# Kubernetes Namespace
resource "kubernetes_namespace" "nullify" {
  count = local.create_kubernetes_resources ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nullify"
    }
  }
}

# Service Account with IRSA annotation
resource "kubernetes_service_account" "nullify_collector_sa" {
  count = local.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.nullify[0].metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.nullify_readonly_role.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "k8s-collector"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nullify"
    }
  }
}

# ClusterRole with read permissions
resource "kubernetes_cluster_role" "nullify_readonly_role" {
  count = local.create_kubernetes_resources ? 1 : 0

  metadata {
    name = "nullify-k8s-collector-role"
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nullify"
    }
  }

  # Core resources
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
      "configmaps",
      "secrets"
    ]
    verbs = ["get", "list"]
  }

  # Networking resources
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list"]
  }

  # Apps resources
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

  # RBAC resources
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

  # Storage resources
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list"]
  }

  # Batch resources
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list"]
  }

  # Autoscaling resources
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list"]
  }

  # Policy resources
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list"]
  }

  # API extensions
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list"]
  }
}

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "nullify_collector_binding" {
  count = local.create_kubernetes_resources ? 1 : 0

  metadata {
    name = "nullify-k8s-collector-binding"
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nullify"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.nullify_readonly_role[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.nullify_collector_sa[0].metadata[0].name
    namespace = kubernetes_namespace.nullify[0].metadata[0].name
  }
}

# CronJob for K8s data collection
resource "kubernetes_cron_job_v1" "k8s_collector" {
  count = local.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = "k8s-info-collector"
    namespace = kubernetes_namespace.nullify[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "k8s-collector"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nullify"
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
          "app.kubernetes.io/part-of"   = "nullify"
        }
      }

      spec {
        # Set a timeout for the job (6 hours)
        active_deadline_seconds = 21600

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name"      = "nullify"
              "app.kubernetes.io/component" = "k8s-collector"
              "app.kubernetes.io/part-of"   = "nullify"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.nullify_collector_sa[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name              = "collector"
              image             = "public.ecr.aws/w4o2j2x4/integrations:latest"
              image_pull_policy = "Always"

              env {
                name = "NODE_NAME"
                value_from {
                  field_ref {
                    field_path = "spec.nodeName"
                  }
                }
              }

              env {
                name  = "NULLIFY_S3_BUCKET_NAME"
                value = var.s3_bucket_name
              }

              env {
                name  = "NULLIFY_S3_KEY_PREFIX"
                value = "k8s-collector"
              }

              env {
                name  = "AWS_REGION"
                value = var.aws_region
              }

              resources {
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
                requests = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
              }

              security_context {
                run_as_non_root            = true
                run_as_user                = 1000
                read_only_root_filesystem  = true
                allow_privilege_escalation = false

                capabilities {
                  drop = ["ALL"]
                }
              }
            }
          }
        }
      }
    }
  }
} 