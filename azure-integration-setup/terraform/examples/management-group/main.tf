# Example: management-group install (recommended). Reader is granted once on
# the management group and Azure inherits it to every subscription underneath.

module "nullify" {
  source = "../../"

  customer_name = "acme-corp"

  scope               = "management_group"
  management_group_id = "acme-root-mg"

  # From the Nullify console (Settings -> Cloud Integrations -> Azure).
  nullify_oidc_issuer_url = "https://gcp.nullify.ai"
  nullify_tenant_id       = "GitHub-XXXXXXXXX"
}

output "application_client_id" {
  value = module.nullify.application_client_id
}

output "entra_tenant_id" {
  value = module.nullify.entra_tenant_id
}
