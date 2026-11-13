# Required Google Cloud APIs on the host project. Without these enabled,
# the very first `terraform apply` against a fresh project fails with
# cryptic 403 errors from the resource-creation calls (e.g. "Workload
# Identity Pools API has not been used in project … before or it is
# disabled"). Enabling them up front lets Terraform create everything in
# one shot.
#
# `disable_on_destroy = false` because these APIs may be in use by other
# resources in the project; disabling them on `terraform destroy` would
# break those.
resource "google_project_service" "required" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudasset.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  project            = var.host_project_id
  service            = each.value
  disable_on_destroy = false
}

# Some Google APIs count every call against the quota of the calling
# service account's own project, not the project that is read. The Nullify
# service account lives in the host project, so these APIs must also be
# enabled here, or every read of them fails with "API has not been used in
# project <host> before or it is disabled". The roles in main.tf, not these
# APIs, decide what Nullify can read. Google can enable dependent APIs with
# them.
#
# Terraform apply fails if any API cannot be enabled.
# Set `enable_scan_quota_apis = false` to manage these APIs separately.
resource "google_project_service" "scan_quota" {
  for_each = var.enable_scan_quota_apis ? toset([
    "cloudkms.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com",
  ]) : toset([])
  project            = var.host_project_id
  service            = each.value
  disable_on_destroy = false
}
