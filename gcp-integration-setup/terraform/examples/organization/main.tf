# Example: organisation-wide install (recommended).

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
