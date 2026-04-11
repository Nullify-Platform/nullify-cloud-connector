# Example: organisation-wide install (recommended).

module "nullify" {
  source = "../../"

  customer_name   = "acme-corp"
  host_project_id = "acme-security"

  scope           = "organization"
  organization_id = "123456789012"

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
