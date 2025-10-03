terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "primary" {
  name = element(split("/", var.eks_cluster_arns[0]), length(split("/", var.eks_cluster_arns[0])) - 1)
}

data "aws_eks_cluster_auth" "primary" {
  name = element(split("/", var.eks_cluster_arns[0]), length(split("/", var.eks_cluster_arns[0])) - 1)
}

data "aws_eks_cluster" "secondary" {
  name = element(split("/", var.eks_cluster_arns[1]), length(split("/", var.eks_cluster_arns[0])) - 1)
}

data "aws_eks_cluster_auth" "secondary" {
  name = element(split("/", var.eks_cluster_arns[1]), length(split("/", var.eks_cluster_arns[0])) - 1)
}

provider "kubernetes" {
  alias                  = "primary"
  host                   = data.aws_eks_cluster.primary.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.primary.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.primary.token
}

provider "kubernetes" {
  alias                  = "secondary"
  host                   = data.aws_eks_cluster.secondary.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.secondary.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.secondary.token
}

module "nullify_aws_integration" {
  source           = "../../modules/nullify-aws-integration"
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn
  aws_region       = var.aws_region
  s3_bucket_name   = var.s3_bucket_name
  kms_key_arn      = var.kms_key_arn

  # Multiple Kubernetes Clusters Configuration
  enable_kubernetes_integration = true
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
  s3_bucket_name       = var.s3_bucket_name
  kms_key_arn          = var.kms_key_arn
  aws_region           = var.aws_region
  kubernetes_namespace = var.kubernetes_namespace
  cronjob_schedule     = var.cronjob_schedule
  collector_image      = var.collector_image
}

module "k8s_resources_secondary" {
  source = "../../modules/k8s-resources"
  providers = {
    kubernetes = kubernetes.secondary
  }
  iam_role_arn         = module.nullify_aws_integration.role_arn
  s3_bucket_name       = var.s3_bucket_name
  kms_key_arn          = var.kms_key_arn
  aws_region           = var.aws_region
  kubernetes_namespace = var.kubernetes_namespace
  cronjob_schedule     = var.cronjob_schedule
  collector_image      = var.collector_image
} 