module "nullify_azure_integration" {
  source = "./modules/nullify-azure-integration"

  customer_name           = var.customer_name
  scope                   = var.scope
  management_group_id     = var.management_group_id
  subscription_ids        = var.subscription_ids
  nullify_oidc_issuer_url = var.nullify_oidc_issuer_url
  nullify_tenant_id       = var.nullify_tenant_id
  application_name        = var.application_name
  enable_directory_read   = var.enable_directory_read
}
