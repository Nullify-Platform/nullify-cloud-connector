resource "kubernetes_namespace" "nullify" {
  count = var.enable_collector ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account" "nullify_collector_sa" {
  count = var.enable_collector ? 1 : 0

  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.nullify[0].metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.iam_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "k8s-collector"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  lifecycle {
    precondition {
      condition     = var.iam_role_arn != ""
      error_message = "iam_role_arn is required when enable_collector is true: the collector's service account assumes it through IRSA."
    }
  }
}

resource "kubernetes_cluster_role" "nullify_readonly_role" {
  count = var.enable_collector ? 1 : 0

  metadata {
    name = "nullify-k8s-collector-role"
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Kinds the collector lists, kept identical to the managed-scan ClusterRole
  # (managed_scan.tf) and to collect.go. "jobs" is granted ahead of the
  # monorepo's fix/k8s-deployment-matching-review stack (#12807 / #12830).
  rule {
    api_groups = [""]
    resources = [
      "pods",
      "services",
      "namespaces",
      "nodes",
      "serviceaccounts",
      "configmaps",
      "secrets",
      "resourcequotas",
      "limitranges",
      "persistentvolumes",
      "persistentvolumeclaims",
    ]
    verbs = ["list"]
  }

  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "replicasets",
      "statefulsets",
      "daemonsets",
    ]
    verbs = ["list"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["list"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources = [
      "ingresses",
      "networkpolicies",
    ]
    verbs = ["list"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["list"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources = [
      "roles",
      "rolebindings",
      "clusterroles",
      "clusterrolebindings",
    ]
    verbs = ["list"]
  }

  rule {
    api_groups = ["admissionregistration.k8s.io"]
    resources = [
      "validatingwebhookconfigurations",
      "mutatingwebhookconfigurations",
      "validatingadmissionpolicies",
      "validatingadmissionpolicybindings",
    ]
    verbs = ["list"]
  }

  rule {
    non_resource_urls = ["/version"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "nullify_collector_binding" {
  count = var.enable_collector ? 1 : 0

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
    name      = kubernetes_cluster_role.nullify_readonly_role[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.nullify_collector_sa[0].metadata[0].name
    namespace = kubernetes_namespace.nullify[0].metadata[0].name
  }
}

resource "kubernetes_cron_job_v1" "k8s_collector" {
  count = var.enable_collector ? 1 : 0

  metadata {
    name      = "k8s-info-collector"
    namespace = kubernetes_namespace.nullify[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "nullify"
      "app.kubernetes.io/component" = "k8s-collector"
    }
  }

  lifecycle {
    precondition {
      condition     = var.cluster_name != ""
      error_message = "cluster_name is required when enable_collector is true. It must match your actual cluster name exactly, as AWS reports it, and it must match a cluster registered on the Nullify configure page: Nullify joins the upload on this name and silently drops or skips it otherwise. It also names the upload, <prefix>/k8s-collector/<cluster_name>-data.json, so collectors without a name all overwrite the same k8s-collector/default-name-data.json object."
    }

    precondition {
      condition     = var.kms_key_arn != ""
      error_message = "kms_key_arn is required when enable_collector is true: the collector walks the cluster, then refuses to upload without KMS encryption and exits 1, so every CronJob run fails and Nullify receives nothing. There is no opt-out. Nullify's upload bucket sets SSE-KMS as its default encryption, so an upload sent with no encryption headers is still encrypted with Nullify's key, and S3 rejects it unless the caller holds kms:GenerateDataKey on that key -- which this role only gets from kms_key_arn. Take the value from the Nullify configure page."
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
            service_account_name = kubernetes_service_account.nullify_collector_sa[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "k8s-collector"
              image = var.collector_image

              env {
                name  = "CLUSTER_NAME"
                value = var.cluster_name
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

              dynamic "env" {
                for_each = var.kms_key_arn != "" ? [1] : []
                content {
                  name  = "NULLIFY_KMS_KEY_ARN"
                  value = var.kms_key_arn
                }
              }

              dynamic "env" {
                for_each = var.enable_debug ? [1] : []
                content {
                  name  = "ENABLE_DEBUG_LOG"
                  value = "true"
                }
              }

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                run_as_non_root            = true

                capabilities {
                  drop = ["ALL"]
                }
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
