module "nullify_gcp_integration" {
  source = "./modules/nullify-gcp-integration"

  customer_name             = var.customer_name
  host_project_id           = var.host_project_id
  scope                     = var.scope
  organization_id           = var.organization_id
  folder_id                 = var.folder_id
  project_ids               = var.project_ids
  nullify_aws_principal_arn = var.nullify_aws_principal_arn
  nullify_aws_account_id    = var.nullify_aws_account_id
  wif_pool_id               = var.wif_pool_id
  wif_provider_id           = var.wif_provider_id
  service_account_name      = var.service_account_name
}
