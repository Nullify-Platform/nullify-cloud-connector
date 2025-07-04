module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"

  # Required variables
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn

  # Optional variables with defaults
  aws_region                    = var.aws_region
  s3_bucket_name                = var.s3_bucket_name
  kms_key_arn                   = var.kms_key_arn
  enable_kubernetes_integration = var.enable_kubernetes_integration
  eks_cluster_arns              = var.eks_cluster_arns
  kubernetes_namespace          = var.kubernetes_namespace
  service_account_name          = var.service_account_name
  cronjob_schedule              = var.cronjob_schedule
  tags                          = var.tags
} 