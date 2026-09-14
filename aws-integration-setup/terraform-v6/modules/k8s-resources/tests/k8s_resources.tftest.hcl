mock_provider "kubernetes" {}

run "collector_only_is_the_default" {
  command = plan

  variables {
    iam_role_arn   = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    s3_bucket_name = "nullify-collector-uploads"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.k8s_collector) == 1 && length(kubernetes_service_account.nullify_collector_sa) == 1
    error_message = "The collector must be deployed by default"
  }

  assert {
    condition     = kubernetes_cron_job_v1.k8s_collector[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].image == "public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.45.0"
    error_message = "The collector image must default to the pinned Nullify ECR Public tag"
  }

  assert {
    condition     = length(kubernetes_cluster_role_v1.nullify_readonly) == 0 && length(kubernetes_cluster_role_binding_v1.nullify_readonly) == 0
    error_message = "Managed-scan RBAC must be opt-in"
  }
}

run "collector_requires_a_role_arn" {
  command = plan

  expect_failures = [kubernetes_service_account.nullify_collector_sa]
}

run "managed_scan_rbac_only" {
  command = plan

  variables {
    enable_collector         = false
    enable_managed_scan_rbac = true
  }

  assert {
    condition     = length(kubernetes_namespace.nullify) == 0 && length(kubernetes_cron_job_v1.k8s_collector) == 0 && length(kubernetes_cluster_role.nullify_readonly_role) == 0
    error_message = "enable_collector = false must remove every collector resource"
  }

  assert {
    condition     = output.namespace_name == null && output.cronjob_name == null
    error_message = "Collector outputs must be null when the collector is disabled"
  }

  assert {
    condition     = length(kubernetes_cluster_role_v1.nullify_readonly[0].rule) == 7
    error_message = "The managed-scan ClusterRole must have six resource rules and one /version rule"
  }

  assert {
    condition     = sum([for rule in slice(kubernetes_cluster_role_v1.nullify_readonly[0].rule, 0, 6) : length(rule.resources)]) == 26
    error_message = "The managed-scan ClusterRole must list exactly the 26 kinds the scanner reads"
  }

  assert {
    condition     = alltrue([for rule in slice(kubernetes_cluster_role_v1.nullify_readonly[0].rule, 0, 6) : tolist(rule.verbs) == tolist(["list"])])
    error_message = "Resource rules must grant list only"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[6].non_resource_urls) == tolist(["/version"]) && tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[6].verbs) == tolist(["get"])
    error_message = "The only non-resource grant must be get /version"
  }

  assert {
    condition     = contains(kubernetes_cluster_role_v1.nullify_readonly[0].rule[0].resources, "secrets") && !contains(flatten([for rule in kubernetes_cluster_role_v1.nullify_readonly[0].rule : rule.resources == null ? [] : rule.resources]), "pods/exec")
    error_message = "The role must list secrets and grant no subresource"
  }

  assert {
    condition     = kubernetes_cluster_role_binding_v1.nullify_readonly[0].subject[0].kind == "Group" && kubernetes_cluster_role_binding_v1.nullify_readonly[0].subject[0].name == "nullify-readonly"
    error_message = "The binding must name the nullify-readonly group"
  }

  assert {
    condition     = kubernetes_cluster_role_v1.nullify_readonly[0].metadata[0].name == "nullify-readonly"
    error_message = "The ClusterRole name must match the Helm chart and manifest"
  }
}

run "kms_alias_arns_are_accepted" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    kms_key_arn  = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }
}

run "invalid_kms_arns_are_rejected" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    kms_key_arn  = "arn:aws:s3:::not-a-key"
  }

  expect_failures = [var.kms_key_arn]
}
