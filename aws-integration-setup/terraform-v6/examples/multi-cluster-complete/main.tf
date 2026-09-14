terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

locals {
  primary_name     = element(split("/", var.eks_cluster_arns[0]), length(split("/", var.eks_cluster_arns[0])) - 1)
  primary_region   = split(":", var.eks_cluster_arns[0])[3]
  secondary_name   = element(split("/", var.eks_cluster_arns[1]), length(split("/", var.eks_cluster_arns[1])) - 1)
  secondary_region = split(":", var.eks_cluster_arns[1])[3]

  collector_upload_target = var.nullify_s3_access_point_arn != "" ? var.nullify_s3_access_point_arn : var.s3_bucket_name

  collector = contains(["collector", "both"], var.scan_mode)
  managed   = contains(["managed", "both"], var.scan_mode)
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "primary" {
  region = local.primary_region
  name   = local.primary_name
}

# The ephemeral token stays out of plan and state (Terraform >= 1.10).
ephemeral "aws_eks_cluster_auth" "primary" {
  region = local.primary_region
  name   = local.primary_name
}

data "aws_eks_cluster" "secondary" {
  region = local.secondary_region
  name   = local.secondary_name
}

ephemeral "aws_eks_cluster_auth" "secondary" {
  region = local.secondary_region
  name   = local.secondary_name
}

provider "kubernetes" {
  alias                  = "primary"
  host                   = data.aws_eks_cluster.primary.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.primary.certificate_authority[0].data)
  token                  = ephemeral.aws_eks_cluster_auth.primary.token
}

provider "kubernetes" {
  alias                  = "secondary"
  host                   = data.aws_eks_cluster.secondary.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.secondary.certificate_authority[0].data)
  token                  = ephemeral.aws_eks_cluster_auth.secondary.token
}

module "nullify_aws_integration" {
  source                      = "../../modules/nullify-aws-integration"
  customer_name               = var.customer_name
  external_id                 = var.external_id
  nullify_role_arn            = var.nullify_role_arn
  aws_region                  = var.aws_region
  s3_bucket_name              = var.s3_bucket_name
  nullify_s3_access_point_arn = var.nullify_s3_access_point_arn
  kms_key_arn                 = var.kms_key_arn

  enable_kubernetes_integration = local.collector
  eks_cluster_arns              = var.eks_cluster_arns
  kubernetes_namespace          = var.kubernetes_namespace
  tags                          = var.tags
}

module "k8s_resources_primary" {
  source = "../../modules/k8s-resources"
  providers = {
    kubernetes = kubernetes.primary
  }
  iam_role_arn         = module.nullify_aws_integration.role_arn
  s3_bucket_name       = local.collector_upload_target
  kms_key_arn          = var.kms_key_arn
  aws_region           = var.aws_region
  kubernetes_namespace = var.kubernetes_namespace
  cronjob_schedule     = var.cronjob_schedule
  collector_image      = var.collector_image

  enable_collector         = local.collector
  enable_managed_scan_rbac = local.managed
}

module "k8s_resources_secondary" {
  source = "../../modules/k8s-resources"
  providers = {
    kubernetes = kubernetes.secondary
  }
  iam_role_arn         = module.nullify_aws_integration.role_arn
  s3_bucket_name       = local.collector_upload_target
  kms_key_arn          = var.kms_key_arn
  aws_region           = var.aws_region
  kubernetes_namespace = var.kubernetes_namespace
  cronjob_schedule     = var.cronjob_schedule
  collector_image      = var.collector_image

  enable_collector         = local.collector
  enable_managed_scan_rbac = local.managed
}

module "eks_managed_scan_access" {
  source = "../../modules/eks-managed-scan-access"
  count  = local.managed ? 1 : 0

  principal_arn       = module.nullify_aws_integration.role_arn
  principal_unique_id = module.nullify_aws_integration.role_unique_id
  cluster_arns        = var.eks_cluster_arns
  nullify_region      = var.nullify_region
  tags                = var.tags
}
