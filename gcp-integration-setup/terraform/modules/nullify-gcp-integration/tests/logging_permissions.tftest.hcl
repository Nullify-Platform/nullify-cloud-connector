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
    condition     = toset([for grant in google_project_iam_member.predefined : grant.role]) == toset(local.predefined_viewer_roles)
    error_message = "Project installs must bind the reviewed project viewer roles."
  }
  assert {
    condition     = toset(keys(google_project_iam_member.custom)) == toset(var.project_ids) && length(google_project_iam_custom_role.nullify_cloud_connector) == 1
    error_message = "Project installs must bind the scoped custom role."
  }
  assert {
    condition = length(setsubtract(toset([
      "iam.serviceAccounts.list",
      "iam.serviceAccountKeys.list",
      "iam.roles.get",
      "iam.roles.list",
      "iam.workloadIdentityPools.list",
      "iam.workloadIdentityPoolProviders.list",
      "resourcemanager.projects.getIamPolicy",
      "artifactregistry.repositories.getIamPolicy",
      "artifactregistry.dockerimages.list",
      "secretmanager.secrets.getIamPolicy",
      "pubsub.subscriptions.getIamPolicy",
      "orgpolicy.policies.list",
      "bigquery.datasets.getIamPolicy",
    ]), google_project_iam_custom_role.nullify_cloud_connector[0].permissions)) == 0
    error_message = "Project custom roles must retain each collector permission previously supplied by Security Reviewer."
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
    condition     = setunion(toset([for grant in google_organization_iam_member.predefined : grant.role]), toset([for grant in google_organization_iam_member.discovery : grant.role])) == toset(concat(local.predefined_viewer_roles, local.discovery_roles))
    error_message = "Organization installs must bind the reviewed viewer and discovery roles."
  }
  assert {
    condition     = length(google_organization_iam_member.custom) == 1 && length(google_organization_iam_custom_role.nullify_cloud_connector) == 1
    error_message = "Organization installs must bind the organization-defined custom role."
  }
  assert {
    condition     = toset([for permission in google_organization_iam_custom_role.nullify_cloud_connector[0].permissions : permission if startswith(permission, "logging.")]) == toset(["logging.sinks.list", "logging.logMetrics.list", "logging.buckets.list"])
    error_message = "Organization custom roles must retain metadata listing without log-entry reads or writes."
  }
  assert {
    condition     = contains(google_organization_iam_custom_role.nullify_cloud_connector[0].permissions, "accesscontextmanager.policies.list")
    error_message = "Organization installs must retain access-policy enumeration."
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
    condition     = setunion(toset([for grant in google_folder_iam_member.predefined : grant.role]), toset([for grant in google_folder_iam_member.discovery : grant.role])) == toset(concat(local.predefined_viewer_roles, local.discovery_roles))
    error_message = "Folder installs must bind the reviewed viewer and discovery roles."
  }
  assert {
    condition     = length(google_folder_iam_member.custom) == 1 && length(google_organization_iam_custom_role.nullify_cloud_connector) == 1
    error_message = "Folder installs must bind the organization-defined custom role."
  }
}
