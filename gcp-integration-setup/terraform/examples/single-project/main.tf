# Example: per-project install (e.g. for proof-of-concept on a single project).

module "nullify" {
  source = "../../"

  customer_name   = "acme-corp"
  host_project_id = "acme-security"

  scope       = "projects"
  project_ids = ["acme-prod"]

  # From the Nullify console.
  nullify_aws_principal_arn = "arn:aws:iam::000000000000:role/nullify-cloud-connector"
  nullify_aws_account_id    = "000000000000"
  tenant_external_id        = "REPLACE_WITH_VALUE_FROM_NULLIFY_CONSOLE"
}

output "service_account_email" {
  value = module.nullify.service_account_email
}

output "workload_identity_provider" {
  value = module.nullify.workload_identity_provider
}
