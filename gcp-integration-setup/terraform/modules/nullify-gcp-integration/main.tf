# Nullify GCP Cloud Connector
#
# This module provisions read-only access to a GCP environment for the Nullify
# Cloud Connector. The trust model is Workload Identity Federation (WIF) with
# AWS as the source — Nullify's lambdas run on AWS and exchange a signed AWS
# STS GetCallerIdentity request for a short-lived GCP access token, then
# impersonate the service account this module creates.
#
# No long-lived secrets are minted by this module. The customer can revoke
# access at any time by deleting the workload identity provider, the service
# account, or both.
#
# Permissions are intentionally read-only and limited to service-configuration
# and network-topology metadata. There are NO data-plane permissions:
#   - storage: bucket metadata only, never object data
#   - secret manager: secret metadata only, never secret payloads
#   - bigquery: dataset metadata only, never table rows
#
# See modules/nullify-gcp-integration/README.md for the full permission list.

locals {
  common_labels = merge(
    {
      managed-by         = "nullify-cloud-connector"
      customer-name      = lower(var.customer_name)
      tenant-external-id = lower(var.tenant_external_id)
    },
    var.labels,
  )

  # Predefined viewer roles granted to the Nullify service account. Each role
  # is named here so an auditor can trace why each binding exists.
  predefined_viewer_roles = [
    # Organisation-wide asset enumeration. Cheapest way to read everything.
    "roles/cloudasset.viewer",

    # Read all IAM bindings, custom roles, deny policies, recommendations.
    "roles/iam.securityReviewer",

    # Generic project viewer — gives read on the long tail of services that
    # don't have a more specific viewer role.
    "roles/viewer",

    # Compute (VPC, instances, firewalls, load balancers, routes, NAT, peering).
    "roles/compute.viewer",

    # GKE clusters and node pools.
    "roles/container.clusterViewer",

    # Cloud SQL instances + replicas.
    "roles/cloudsql.viewer",

    # Spanner instances + databases.
    "roles/spanner.viewer",

    # KMS key rings + crypto keys.
    "roles/cloudkms.viewer",

    # Logging sinks + exclusions (config only — no log payload access).
    "roles/logging.viewer",

    # Cloud Run services + revisions.
    "roles/run.viewer",

    # Cloud Functions config (function metadata, source URLs).
    "roles/cloudfunctions.viewer",

    # App Engine services + versions.
    "roles/appengine.appViewer",

    # Dataproc clusters and jobs.
    "roles/dataproc.viewer",

    # Dataflow jobs.
    "roles/dataflow.viewer",

    # Pub/Sub topics + subscriptions.
    "roles/pubsub.viewer",
  ]
}

# ---------------------------------------------------------------------------
# Custom role: long-tail read permissions Nullify needs that are not covered
# by any predefined viewer role. Strict allowlist of *.get / *.list only.
# ---------------------------------------------------------------------------

resource "google_project_iam_custom_role" "nullify_cloud_connector" {
  project     = var.host_project_id
  role_id     = "nullifyCloudConnector"
  title       = "Nullify Cloud Connector (read-only)"
  description = "Read-only access to security-relevant config Nullify needs that is not covered by predefined viewer roles."
  stage       = "GA"

  permissions = [
    # Cloud Armor security policies (ingress WAF rules).
    "compute.securityPolicies.get",
    "compute.securityPolicies.list",

    # VPC Service Controls perimeters and access policies.
    "accesscontextmanager.accessPolicies.get",
    "accesscontextmanager.accessPolicies.list",
    "accesscontextmanager.servicePerimeters.get",
    "accesscontextmanager.servicePerimeters.list",

    # Organisation policies.
    "orgpolicy.policies.list",
    "orgpolicy.policy.get",

    # AlloyDB clusters + instances.
    "alloydb.clusters.get",
    "alloydb.clusters.list",
    "alloydb.instances.get",
    "alloydb.instances.list",

    # Filestore instances.
    "file.instances.get",
    "file.instances.list",

    # Memorystore (Redis + Memcache) instances.
    "redis.instances.get",
    "redis.instances.list",
    "memcache.instances.get",
    "memcache.instances.list",

    # Artifact Registry repositories (metadata only — no image content).
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.list",

    # Cloud DNS managed zones + record sets.
    "dns.managedZones.get",
    "dns.managedZones.list",
    "dns.resourceRecordSets.list",

    # API Gateway gateways + APIs + configs.
    "apigateway.gateways.get",
    "apigateway.gateways.list",
    "apigateway.apis.get",
    "apigateway.apis.list",
    "apigateway.apiconfigs.get",
    "apigateway.apiconfigs.list",
  ]
}

# ---------------------------------------------------------------------------
# Service account that Nullify impersonates after the WIF token exchange.
# ---------------------------------------------------------------------------

resource "google_service_account" "nullify_cloud_connector" {
  project      = var.host_project_id
  account_id   = var.service_account_name
  display_name = "Nullify Cloud Connector"
  description  = "Read-only service account impersonated by Nullify via Workload Identity Federation. Managed by Terraform."
}

# ---------------------------------------------------------------------------
# Workload Identity Pool + Provider trusting the Nullify AWS principal.
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "nullify" {
  project                   = var.host_project_id
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "Nullify Cloud Connector"
  description               = "Workload identity pool for the Nullify Cloud Connector. Trusts an AWS IAM role from Nullify's AWS account."
}

resource "google_iam_workload_identity_pool_provider" "nullify_aws" {
  project                            = var.host_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.nullify.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "Nullify AWS"
  description                        = "Trusts the Nullify AWS IAM role for federated access."

  # AWS source — Nullify's lambdas run on AWS and present a signed STS
  # GetCallerIdentity request as the subject token.
  aws {
    account_id = var.nullify_aws_account_id
  }

  # Restrict the trust to the exact AWS IAM role Nullify uses. The
  # attribute condition runs after Google has validated the signed AWS STS
  # request, so a Nullify-account principal that is NOT this role will be
  # rejected.
  attribute_condition = "attribute.aws_role == \"arn:aws:sts::${var.nullify_aws_account_id}:assumed-role/${replace(var.nullify_aws_principal_arn, "/^arn:aws:iam::[0-9]+:role\\//", "")}\""

  attribute_mapping = {
    "google.subject"     = "assertion.arn"
    "attribute.aws_role" = "assertion.arn.contains(\"assumed-role\") ? assertion.arn.extract(\"{anything}assumed-role/\") + \"assumed-role/\" + assertion.arn.extract(\"assumed-role/{role}/\") : assertion.arn"
    "attribute.account"  = "assertion.account"
  }
}

# Allow the Nullify AWS principal (after exchange) to impersonate the
# Nullify service account.
resource "google_service_account_iam_member" "nullify_workload_identity_user" {
  service_account_id = google_service_account.nullify_cloud_connector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.nullify.name}/attribute.aws_role/arn:aws:sts::${var.nullify_aws_account_id}:assumed-role/${replace(var.nullify_aws_principal_arn, "/^arn:aws:iam::[0-9]+:role\\//", "")}"
}

# ---------------------------------------------------------------------------
# Role bindings — organisation scope.
# ---------------------------------------------------------------------------

resource "google_organization_iam_member" "predefined" {
  for_each = var.scope == "organization" ? toset(local.predefined_viewer_roles) : toset([])
  org_id   = var.organization_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}

resource "google_organization_iam_member" "custom" {
  count  = var.scope == "organization" ? 1 : 0
  org_id = var.organization_id
  role   = google_project_iam_custom_role.nullify_cloud_connector.name
  member = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}

# ---------------------------------------------------------------------------
# Role bindings — per-project scope.
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "predefined" {
  for_each = var.scope == "projects" ? {
    for pair in setproduct(var.project_ids, local.predefined_viewer_roles) :
    "${pair[0]}|${pair[1]}" => { project = pair[0], role = pair[1] }
  } : {}
  project = each.value.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}

resource "google_project_iam_member" "custom" {
  for_each = var.scope == "projects" ? toset(var.project_ids) : toset([])
  project  = each.value
  role     = google_project_iam_custom_role.nullify_cloud_connector.name
  member   = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}
