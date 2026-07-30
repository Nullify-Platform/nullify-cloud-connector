# Example: per-subscription install (e.g. a proof of concept on a single
# subscription). Reader is granted directly on each subscription GUID.

module "nullify" {
  source = "../../"

  customer_name = "acme-corp"

  scope            = "subscriptions"
  subscription_ids = ["00000000-0000-0000-0000-000000000000"]

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
