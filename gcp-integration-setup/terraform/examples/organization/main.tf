# Example: organisation-wide install (recommended, one-shot deployment).
#
# Set scope = "organization" to cover every project in the organisation with a
# single terraform apply. Nullify automatically discovers current projects and
# any projects created later — no need to update this configuration or re-run
# Terraform when new projects are added to the organisation.

module "nullify" {
  source = "../../"

  customer_name   = "acme-corp"
  host_project_id = "acme-security"

  scope           = "organization"
  organization_id = "123456789012"

  # From the Nullify console (Settings -> Cloud Integrations -> GCP).
  nullify_oidc_issuer_uri = "https://gcp.nullify.ai"
  nullify_tenant_id       = "Nullify-XXXXXXXXXXXX"
}

output "service_account_email" {
  value = module.nullify.service_account_email
}

output "workload_identity_provider" {
  value = module.nullify.workload_identity_provider
}
