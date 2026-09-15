locals {
  # The kinds Nullify's managed EKS scan lists. Any other manifest or chart that
  # grants this role must list exactly these kinds; the test suite pins the set.
  managed_scan_rules = [
    {
      api_groups = [""]
      resources  = ["nodes", "namespaces", "pods", "services", "persistentvolumeclaims", "persistentvolumes", "configmaps", "secrets", "resourcequotas", "limitranges", "serviceaccounts"]
    },
    {
      api_groups = ["apps"]
      resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    },
    {
      api_groups = ["networking.k8s.io"]
      resources  = ["ingresses", "networkpolicies"]
    },
    {
      api_groups = ["discovery.k8s.io"]
      resources  = ["endpointslices"]
    },
    {
      api_groups = ["rbac.authorization.k8s.io"]
      resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    },
    {
      api_groups = ["admissionregistration.k8s.io"]
      resources  = ["validatingwebhookconfigurations", "mutatingwebhookconfigurations", "validatingadmissionpolicies", "validatingadmissionpolicybindings"]
    },
    {
      api_groups = ["batch"]
      resources  = ["jobs"]
    },
  ]
}

resource "kubernetes_cluster_role_v1" "nullify_readonly" {
  count = var.enable_managed_scan_rbac ? 1 : 0

  metadata {
    name = var.managed_scan_cluster_role_name
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "managed-scan-rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  dynamic "rule" {
    for_each = local.managed_scan_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = ["list"]
    }
  }

  rule {
    non_resource_urls = ["/version"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "nullify_readonly" {
  count = var.enable_managed_scan_rbac ? 1 : 0

  metadata {
    name = var.managed_scan_cluster_role_binding_name
    labels = {
      "app.kubernetes.io/name"       = "nullify"
      "app.kubernetes.io/component"  = "managed-scan-rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.nullify_readonly[0].metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = var.managed_scan_kubernetes_group
  }
}
