mock_provider "kubernetes" {}

run "collector_only_is_the_default" {
  command = plan

  variables {
    iam_role_arn   = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name   = "acme-prod"
    s3_bucket_name = "nullify-collector-uploads"
    kms_key_arn    = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  assert {
    condition     = length([for env in kubernetes_cron_job_v1.k8s_collector[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].env : env if env.name == "CLUSTER_NAME" && env.value == "acme-prod"]) == 1
    error_message = "The CronJob must set CLUSTER_NAME: it names the upload, and collectors without one all write k8s-collector/default-name-data.json"
  }

  assert {
    condition     = length([for env in kubernetes_cron_job_v1.k8s_collector[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].env : env if env.name == "ALLOW_UNENCRYPTED_UPLOAD"]) == 0
    error_message = "ALLOW_UNENCRYPTED_UPLOAD must never be set: the module has no unencrypted path, and Nullify's bucket defaults to SSE-KMS so an unencrypted upload is rejected by KMS anyway"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.k8s_collector) == 1 && length(kubernetes_service_account.nullify_collector_sa) == 1
    error_message = "The collector must be deployed by default"
  }

  assert {
    condition     = kubernetes_cron_job_v1.k8s_collector[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].image == "public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.46.0"
    error_message = "The collector image must default to the pinned Nullify ECR Public tag"
  }

  assert {
    condition     = length(kubernetes_cluster_role_v1.nullify_readonly) == 0 && length(kubernetes_cluster_role_binding_v1.nullify_readonly) == 0
    error_message = "Managed-scan RBAC must be opt-in"
  }
}

run "collector_requires_a_role_arn" {
  command = plan

  variables {
    cluster_name = "acme-prod"
    kms_key_arn  = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  expect_failures = [kubernetes_service_account.nullify_collector_sa]
}

run "collector_requires_a_cluster_name" {
  command = plan

  variables {
    iam_role_arn   = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    s3_bucket_name = "nullify-collector-uploads"
    kms_key_arn    = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  expect_failures = [kubernetes_cron_job_v1.k8s_collector]
}

# The published collector images exit 1 on upload with "upload blocked: no KMS
# encryption and unencrypted uploads not explicitly allowed" when the key is
# missing, after a successful collection. Failing at plan is the only signal
# the customer gets before that.
run "collector_requires_a_kms_key" {
  command = plan

  variables {
    iam_role_arn   = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name   = "acme-prod"
    s3_bucket_name = "nullify-collector-uploads"
  }

  expect_failures = [kubernetes_cron_job_v1.k8s_collector]
}

run "collector_and_managed_scan_rbac_cannot_both_run" {
  command = plan

  variables {
    iam_role_arn             = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name             = "acme-prod"
    s3_bucket_name           = "nullify-collector-uploads"
    kms_key_arn              = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
    enable_collector         = true
    enable_managed_scan_rbac = true
  }

  expect_failures = [kubernetes_cluster_role_v1.nullify_readonly]
}

run "the_kms_key_reaches_the_collector" {
  command = plan

  variables {
    iam_role_arn   = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name   = "acme-prod"
    s3_bucket_name = "nullify-collector-uploads"
    kms_key_arn    = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }

  assert {
    condition     = length([for env in kubernetes_cron_job_v1.k8s_collector[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].env : env if env.name == "NULLIFY_KMS_KEY_ARN" && env.value == "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"]) == 1
    error_message = "kms_key_arn must reach the collector as NULLIFY_KMS_KEY_ARN, which S3 takes as SSEKMSKeyId"
  }
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

  # Pins the set, not just the size: swapping one kind for another keeps every
  # count assertion green. Anything else that binds this group -- a chart, a
  # manifest -- has to grant exactly these kinds.
  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[0].api_groups) == tolist([""]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[0].resources) == toset(["nodes", "namespaces", "pods", "services", "persistentvolumeclaims", "persistentvolumes", "configmaps", "secrets", "resourcequotas", "limitranges", "serviceaccounts"])
    error_message = "Rule 0 must grant exactly the core API group kinds the scanner lists"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[1].api_groups) == tolist(["apps"]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[1].resources) == toset(["deployments", "daemonsets", "statefulsets", "replicasets"])
    error_message = "Rule 1 must grant exactly the apps API group kinds the scanner lists"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[2].api_groups) == tolist(["networking.k8s.io"]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[2].resources) == toset(["ingresses", "networkpolicies"])
    error_message = "Rule 2 must grant exactly the networking.k8s.io API group kinds the scanner lists"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[3].api_groups) == tolist(["discovery.k8s.io"]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[3].resources) == toset(["endpointslices"])
    error_message = "Rule 3 must grant exactly the discovery.k8s.io API group kinds the scanner lists"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[4].api_groups) == tolist(["rbac.authorization.k8s.io"]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[4].resources) == toset(["roles", "rolebindings", "clusterroles", "clusterrolebindings"])
    error_message = "Rule 4 must grant exactly the rbac.authorization.k8s.io API group kinds the scanner lists"
  }

  assert {
    condition     = tolist(kubernetes_cluster_role_v1.nullify_readonly[0].rule[5].api_groups) == tolist(["admissionregistration.k8s.io"]) && toset(kubernetes_cluster_role_v1.nullify_readonly[0].rule[5].resources) == toset(["validatingwebhookconfigurations", "mutatingwebhookconfigurations", "validatingadmissionpolicies", "validatingadmissionpolicybindings"])
    error_message = "Rule 5 must grant exactly the admissionregistration.k8s.io API group kinds the scanner lists"
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
    error_message = "The ClusterRole name must stay nullify-readonly: it is the name every other install path for this role uses"
  }
}

run "kms_alias_arns_are_accepted" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name = "acme-prod"
    kms_key_arn  = "arn:aws:kms:eu-central-1:111122223333:alias/nullify-customer-uploads"
  }
}

run "invalid_kms_arns_are_rejected" {
  command = plan

  variables {
    iam_role_arn = "arn:aws:iam::123456789012:role/AWSIntegration-acme-NullifyReadOnlyRole"
    cluster_name = "acme-prod"
    kms_key_arn  = "arn:aws:s3:::not-a-key"
  }

  expect_failures = [var.kms_key_arn]
}
