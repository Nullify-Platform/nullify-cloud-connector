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

# Optional scan-target API. Firestore / Datastore-mode database discovery
# (datastore.databases.list/getMetadata) requires the Firestore API to be
# enabled on the project. Gated behind a flag and off by default so the
# connector never turns on an API for a service the customer may not use —
# the datastore.* read permissions are granted regardless. Set
# enable_firestore_api = true to opt in.
resource "google_project_service" "firestore" {
  count              = var.enable_firestore_api ? 1 : 0
  project            = var.host_project_id
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}
