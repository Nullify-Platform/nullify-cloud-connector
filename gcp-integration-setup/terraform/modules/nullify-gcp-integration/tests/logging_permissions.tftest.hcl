mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
}

variables {
  customer_name           = "marketplace-test"
  host_project_id         = "nullify-test"
  nullify_oidc_issuer_uri = "https://gcp.nullify.ai"
  nullify_tenant_id       = "tenant-test"
  project_ids             = ["nullify-test"]
}

run "project_logging_metadata_only" {
  command = plan
  variables { scope = "projects" }

  assert {
    condition     = alltrue([for grant in google_project_iam_member.predefined : grant.role != "roles/logging.viewer"])
    error_message = "Project installs must not grant log-entry access through Logs Viewer."
  }
  assert {
    condition     = toset([for permission in google_project_iam_custom_role.nullify_cloud_connector[0].permissions : permission if startswith(permission, "logging.")]) == toset(["logging.sinks.list", "logging.logMetrics.list", "logging.buckets.list"])
    error_message = "Logging collection must retain metadata listing without log-entry reads or writes."
  }
}

run "organization_logging_metadata_only" {
  command = plan
  variables {
    scope           = "organization"
    organization_id = "123456789012"
  }
  assert {
    condition     = alltrue([for grant in google_organization_iam_member.predefined : grant.role != "roles/logging.viewer"])
    error_message = "Organization installs must not grant Logs Viewer."
  }
  assert {
    condition     = toset([for permission in google_organization_iam_custom_role.nullify_cloud_connector[0].permissions : permission if startswith(permission, "logging.")]) == toset(["logging.sinks.list", "logging.logMetrics.list", "logging.buckets.list"])
    error_message = "Organization custom roles must retain metadata listing without log-entry reads or writes."
  }
}

run "folder_logging_metadata_only" {
  command = plan
  variables {
    scope           = "folder"
    organization_id = "123456789012"
    folder_id       = "987654321"
  }
  assert {
    condition     = alltrue([for grant in google_folder_iam_member.predefined : grant.role != "roles/logging.viewer"])
    error_message = "Folder installs must not grant Logs Viewer."
  }
  assert {
    condition     = length(google_organization_iam_custom_role.nullify_cloud_connector) == 1 && length(google_folder_iam_member.custom) == 1
    error_message = "Folder installs must retain the organization-defined custom role binding."
  }
}
