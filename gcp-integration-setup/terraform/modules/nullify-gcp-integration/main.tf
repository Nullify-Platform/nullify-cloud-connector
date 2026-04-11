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

# ---------------------------------------------------------------------------
# Input validation that needs to look at multiple variables. Per-variable
# `validation` blocks can't reference other vars, so we use a no-op
# terraform_data resource with `precondition` checks instead.
# ---------------------------------------------------------------------------

resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition     = var.scope != "organization" || var.organization_id != ""
      error_message = "scope = \"organization\" requires organization_id to be set."
    }
    precondition {
      condition     = var.scope != "folder" || var.folder_id != ""
      error_message = "scope = \"folder\" requires folder_id to be set."
    }
    precondition {
      condition     = var.scope != "folder" || var.organization_id != ""
      error_message = "scope = \"folder\" requires organization_id to be set so the long-tail custom role can be defined at the organisation and granted on the folder."
    }
    precondition {
      condition     = var.scope != "projects" || length(var.project_ids) > 0
      error_message = "scope = \"projects\" requires project_ids to be non-empty."
    }
    precondition {
      # If any project_id is different from host_project_id, the custom role
      # must be assignable across projects, which requires the org-level
      # variant. Block the apply early rather than having terraform try to
      # bind a project-scoped custom role on a sibling project.
      condition     = var.scope != "projects" || var.organization_id != "" || alltrue([for p in var.project_ids : p == var.host_project_id])
      error_message = "scope = \"projects\" with project_ids that include any project other than host_project_id requires organization_id to be set, because the custom role must be defined at the organisation to be assignable across projects."
    }
  }
}

locals {
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

  # Robust extraction of the friendly role name from the Nullify principal
  # ARN. The previous regex (`/^arn:aws:iam::[0-9]+:role\\//`) silently broke
  # if the role were ever issued under a path (e.g. `role/some/path/Name`),
  # because it would leave `some/path/Name` and the assumed-role assertion
  # arrives without a path component. The split-and-take-last approach is
  # path-tolerant: arn:aws:iam::000000000000:role/some/path/RoleName → RoleName.
  nullify_aws_role_name = element(reverse(split("/", var.nullify_aws_principal_arn)), 0)

  # When organization_id is set, the custom role can be defined at the
  # organisation and granted on any project/folder/org within it. This is
  # the only way `scope = "projects"` with multiple project_ids (or with a
  # project_id != host_project_id) can work, because a project-scoped custom
  # role is only assignable on resources inside that project.
  use_org_custom_role = var.organization_id != ""

  # The fully qualified custom-role ID downstream bindings reference. We
  # build it once here so the bindings don't have to know which of the two
  # custom-role resources actually exists.
  custom_role_id = local.use_org_custom_role ? google_organization_iam_custom_role.nullify_cloud_connector[0].id : google_project_iam_custom_role.nullify_cloud_connector[0].id

  # The full set of permissions Nullify needs above and beyond the predefined
  # viewer roles. Strict allowlist of *.get / *.list only — no mutations and
  # no data-plane reads.
  custom_role_permissions = [
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
# Custom role: long-tail read permissions Nullify needs that are not covered
# by any predefined viewer role.
#
# Two variants exist because GCP's IAM model is unforgiving here:
#   - google_project_iam_custom_role only assignable on resources within the
#     defining project. Fine for single-project installs.
#   - google_organization_iam_custom_role assignable on any project, folder,
#     or the org itself. Required for org-scope, folder-scope, and any
#     multi-project install.
#
# Selection is keyed off var.organization_id: providing it switches to the
# org-level role automatically. The previous bug was creating only the
# project-level role and trying to grant it at the org / on cross-project
# bindings, which fails at apply time.
# ---------------------------------------------------------------------------

resource "google_organization_iam_custom_role" "nullify_cloud_connector" {
  count       = local.use_org_custom_role ? 1 : 0
  org_id      = var.organization_id
  role_id     = "nullifyCloudConnector"
  title       = "Nullify Cloud Connector (read-only)"
  description = "Read-only access to security-relevant config Nullify needs that is not covered by predefined viewer roles."
  stage       = "GA"
  permissions = local.custom_role_permissions
}

resource "google_project_iam_custom_role" "nullify_cloud_connector" {
  count       = local.use_org_custom_role ? 0 : 1
  project     = var.host_project_id
  role_id     = "nullifyCloudConnector"
  title       = "Nullify Cloud Connector (read-only)"
  description = "Read-only access to security-relevant config Nullify needs that is not covered by predefined viewer roles."
  stage       = "GA"
  permissions = local.custom_role_permissions
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
  attribute_condition = "attribute.aws_role == \"arn:aws:sts::${var.nullify_aws_account_id}:assumed-role/${local.nullify_aws_role_name}\""

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
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.nullify.name}/attribute.aws_role/arn:aws:sts::${var.nullify_aws_account_id}:assumed-role/${local.nullify_aws_role_name}"
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
  role   = local.custom_role_id
  member = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}

# ---------------------------------------------------------------------------
# Role bindings — folder scope.
#
# Folder-scoped installs are common when an org carves its hierarchy into
# functional folders (e.g. `security/`, `prod/`) and the customer wants
# Nullify pinned to one of those without going org-wide. The custom role
# must come from the org-level resource for this to apply, so org_id is
# required when scope = "folder".
# ---------------------------------------------------------------------------

resource "google_folder_iam_member" "predefined" {
  for_each = var.scope == "folder" ? toset(local.predefined_viewer_roles) : toset([])
  folder   = var.folder_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}

resource "google_folder_iam_member" "custom" {
  count  = var.scope == "folder" ? 1 : 0
  folder = var.folder_id
  role   = local.custom_role_id
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
  role     = local.custom_role_id
  member   = "serviceAccount:${google_service_account.nullify_cloud_connector.email}"
}
