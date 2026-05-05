# Nullify GCP Cloud Connector
#
# This module provisions read-only access to a GCP environment for the Nullify
# Cloud Connector. The trust model is Workload Identity Federation (WIF) with
# OIDC as the source — Nullify acts as an OpenID Connect identity provider,
# minting a per-tenant RS256 JWT with `tenant_id` as a custom claim. The
# subject token is exchanged via Google STS for a short-lived federated
# access token, then used to impersonate the service account this module
# creates. The pool's `attribute_condition` pins trust to the customer's
# specific Nullify tenant id, so even if Nullify's signing key were stolen
# an attacker could not mint a token accepted by another tenant's provider.
#
# No long-lived secrets are minted by this module. The customer can revoke
# access at any time by deleting the workload identity provider, the service
# account, or both.
#
# Permissions are intentionally read-only and limited to service-configuration
# and network-topology metadata. There are NO data-plane permissions:
#   - storage: bucket metadata only, never object data
#   - secret manager: secret metadata only, never secret payloads
#   - bigquery: schema/IAM only, never table rows
#   - workflows: workflow definitions only, never execution inputs/outputs
#   - firestore: database list only, never document contents
#   - vertex ai: endpoint config only, never inference inputs/outputs
#   - security command center: source config only, never finding contents
#
# See ../../docs/permissions.md for the full permission list + rationale.

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

  # Permissions valid in both org- and project-scoped custom roles. Strict
  # allowlist of *.get / *.list only — no mutations and no data-plane reads.
  custom_role_permissions_common = [
    # Cloud Armor security policies (ingress WAF rules).
    "compute.securityPolicies.get",
    "compute.securityPolicies.list",

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

    # Cloud Storage bucket settings + bucket-level IAM (no object data —
    # storage.objects.* is intentionally not granted).
    "storage.buckets.get",
    "storage.buckets.list",
    "storage.buckets.getIamPolicy",

    # Secret Manager: secret name, labels, replication policy, rotation
    # config (no secretmanager.versions.access — payloads are never read).
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",

    # BigQuery dataset/table/routine schema + IAM. No bigquery.tables.getData
    # (row data) and no bigquery.jobs.create (no query execution / billing).
    "bigquery.datasets.get",
    "bigquery.datasets.list",
    "bigquery.tables.get",
    "bigquery.tables.list",
    "bigquery.routines.get",
    "bigquery.routines.list",

    # Cloud Build trigger config (repo binding, file filter, substitutions).
    # No build logs, artifacts, or source contents.
    "cloudbuild.buildTriggers.get",
    "cloudbuild.buildTriggers.list",

    # Cloud Batch job spec. No task logs or output artifacts.
    "batch.jobs.get",
    "batch.jobs.list",

    # Cloud Workflows: workflow definitions only. workflows.executions.* and
    # workflows.stepEntries.* are intentionally NOT granted — execution
    # arguments and step inputs/outputs are runtime data.
    "workflows.workflows.get",
    "workflows.workflows.list",

    # Firestore: database list + metadata. datastore.entities.* is
    # intentionally NOT granted — document contents are runtime data.
    # (Note: GCP uses the datastore.* IAM family for Firestore in both
    # Native and Datastore modes; firestore.* may be added later as GCP
    # migrates the IAM surface.)
    "datastore.databases.getMetadata",
    "datastore.databases.list",

    # Vertex AI: endpoint deployment config only. aiplatform.endpoints.predict
    # / computeTokens and all dataset/featurestore/model perms are
    # intentionally NOT granted.
    "aiplatform.endpoints.get",
    "aiplatform.endpoints.list",

    # Security Command Center: source config (which detection sources are
    # wired up). securitycenter.findings.* and securitycenter.assets.* are
    # intentionally NOT granted — finding contents are runtime data.
    # Org-scope only — at project scope these calls return empty harmlessly.
    "securitycenter.sources.get",
    "securitycenter.sources.list",
  ]

  # Permissions only includable in an org-scoped custom role. GCP rejects
  # these in a project-scoped custom role with "Permission ... is not valid"
  # because the underlying resources (VPC SC access policies / perimeters,
  # org policies) live at organisation scope.
  custom_role_permissions_org_only = [
    # VPC Service Controls perimeters and access policies.
    "accesscontextmanager.accessPolicies.get",
    "accesscontextmanager.accessPolicies.list",
    "accesscontextmanager.servicePerimeters.get",
    "accesscontextmanager.servicePerimeters.list",

    # Organisation policies.
    "orgpolicy.policies.list",
    "orgpolicy.policy.get",
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
  permissions = concat(local.custom_role_permissions_common, local.custom_role_permissions_org_only)
}

resource "google_project_iam_custom_role" "nullify_cloud_connector" {
  count       = local.use_org_custom_role ? 0 : 1
  project     = var.host_project_id
  role_id     = "nullifyCloudConnector"
  title       = "Nullify Cloud Connector (read-only)"
  description = "Read-only access to security-relevant config Nullify needs that is not covered by predefined viewer roles."
  stage       = "GA"
  permissions = local.custom_role_permissions_common

  # iam.googleapis.com must be enabled before a custom role can be created.
  # Other resources in this module already declare this dependency; the
  # project-scoped custom role was the odd one out and could race the API
  # enable on a fresh project.
  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Service account that Nullify impersonates after the WIF token exchange.
# ---------------------------------------------------------------------------

resource "google_service_account" "nullify_cloud_connector" {
  project      = var.host_project_id
  account_id   = var.service_account_name
  display_name = "Nullify Cloud Connector"
  description  = "Read-only service account impersonated by Nullify via Workload Identity Federation. Managed by Terraform."

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Workload Identity Pool + OIDC Provider trusting Nullify's OIDC issuer.
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "nullify" {
  project                   = var.host_project_id
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "Nullify Cloud Connector"
  description               = "Workload identity pool for the Nullify Cloud Connector. Trusts Nullify's OIDC issuer for the customer's specific tenant id."

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "nullify_oidc" {
  project                            = var.host_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.nullify.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "Nullify OIDC"
  description                        = "Trusts Nullify's OIDC issuer for federated access scoped to this tenant."

  # OIDC source — Nullify mints a signed RS256 JWT in-process and presents
  # it as the subject token. Google STS fetches the JWKS document from
  # `${nullify_oidc_issuer_uri}/.well-known/jwks.json` to verify the
  # signature, then evaluates the attribute_condition below before issuing
  # a federated access token.
  oidc {
    issuer_uri = var.nullify_oidc_issuer_uri
  }

  # Pin trust to this specific Nullify tenant. Nullify's OIDC issuer is
  # multi-tenant; the JWT carries a `tenant_id` custom claim. Without this
  # condition any Nullify tenant could exchange a token against this
  # provider. With it, even if Nullify's signing key were stolen, an
  # attacker could not mint a token accepted by another tenant's provider.
  attribute_condition = "assertion.tenant_id == \"${var.nullify_tenant_id}\""

  attribute_mapping = {
    "google.subject"      = "assertion.sub"
    "attribute.tenant_id" = "assertion.tenant_id"
  }

  depends_on = [google_project_service.required]
}

# Allow the Nullify federated principal scoped to this tenant id to
# impersonate the Nullify service account. principalSet on `attribute.tenant_id`
# is the per-tenant binding that makes the integration safe in a
# multi-tenant Nullify deployment.
resource "google_service_account_iam_member" "nullify_workload_identity_user" {
  service_account_id = google_service_account.nullify_cloud_connector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.nullify.name}/attribute.tenant_id/${var.nullify_tenant_id}"
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
