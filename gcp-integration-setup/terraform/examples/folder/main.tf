# Example: folder-scoped install. Use this when your GCP hierarchy is carved
# up by folder (e.g. a dedicated `security/` or `prod/` folder) and you want
# Nullify pinned to one of those folders without going org-wide.
#
# `organization_id` is required even though the bindings are folder-scoped:
# the long-tail custom role must be defined at the organisation so it can
# be assigned on the folder.

module "nullify" {
  source = "../../"

  customer_name   = "acme-corp"
  host_project_id = "acme-security"

  scope           = "folder"
  organization_id = "123456789012"
  folder_id       = "987654321098"

  # From the Nullify console.
  nullify_aws_principal_arn = "arn:aws:iam::000000000000:role/nullify-cloud-connector"
  nullify_aws_account_id    = "000000000000"
}

output "service_account_email" {
  value = module.nullify.service_account_email
}

output "workload_identity_provider" {
  value = module.nullify.workload_identity_provider
}
