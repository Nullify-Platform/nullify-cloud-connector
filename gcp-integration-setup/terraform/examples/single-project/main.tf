# Example: per-project install (e.g. for a proof of concept on a single
# project). The `host_project_id` and the only entry in `project_ids` MUST
# match — granting on cross-project bindings requires `organization_id` to
# be set so the long-tail custom role can be defined at the org level.

module "nullify" {
  source = "../../"

  customer_name   = "acme-corp"
  host_project_id = "acme-security"

  scope       = "projects"
  project_ids = ["acme-security"]

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
