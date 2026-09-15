module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"

  # Required variables
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn

  # Optional variables with defaults
  aws_region                    = var.aws_region
  s3_bucket_name                = var.s3_bucket_name
  nullify_s3_access_point_arn   = var.nullify_s3_access_point_arn
  kms_key_arn                   = var.kms_key_arn
  enable_kubernetes_integration = var.enable_kubernetes_integration
  eks_cluster_arns              = var.eks_cluster_arns
  eks_oidc_issuer_urls          = var.eks_oidc_issuer_urls
  kubernetes_namespace          = var.kubernetes_namespace
  service_account_name          = var.service_account_name
  tags                          = var.tags
}

module "eks_managed_scan_access" {
  source = "./modules/eks-managed-scan-access"
  count  = var.enable_managed_scan ? 1 : 0

  principal_arn         = module.nullify_aws_integration.role_arn
  principal_unique_id   = module.nullify_aws_integration.role_unique_id
  cluster_arns          = var.managed_scan_cluster_arns
  nullify_region        = var.nullify_region
  authorization         = var.managed_scan_authorization
  kubernetes_group_name = var.managed_scan_kubernetes_group
  tags                  = var.tags
}
