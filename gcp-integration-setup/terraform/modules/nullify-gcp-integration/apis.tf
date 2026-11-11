# Required Google Cloud APIs on the host project. Without these enabled,
# the very first `terraform apply` against a fresh project fails with
# cryptic 403 errors from the resource-creation calls (e.g. "Workload
# Identity Pools API has not been used in project … before or it is
# disabled"). Enabling them up front lets Terraform create everything in
# one shot.
#
# Some Google APIs count every call against the quota of the calling
# service account's own project, not the project that is read. The Nullify
# service account lives in the host project, so those APIs must also be
# enabled here, or every read of them fails with "API has not been used in
# project <host> before or it is disabled". Enabling an API grants no access:
# the read-only roles below still decide what Nullify can read.
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

    # Read through the host project's quota.
    "cloudkms.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com",
  ])
  project            = var.host_project_id
  service            = each.value
  disable_on_destroy = false
}
