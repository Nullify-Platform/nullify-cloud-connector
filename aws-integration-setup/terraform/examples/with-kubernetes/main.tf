# Complete Example: Nullify AWS Integration with EKS

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

# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Data source for EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

# Kubernetes Provider configured for EKS
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Extract OIDC provider ID from cluster OIDC issuer URL
locals {
  oidc_provider_id = split("/", data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer)[4]
}

module "nullify_aws_integration" {
  source = "../../modules/nullify-aws-integration"

  # Required variables
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn

  # AWS Configuration
  aws_region = var.aws_region

  # Kubernetes Configuration
  enable_kubernetes_integration = true
  eks_oidc_id                   = local.oidc_provider_id
  kubernetes_namespace          = var.kubernetes_namespace
  service_account_name          = var.service_account_name
  cronjob_schedule              = var.cronjob_schedule

  # Custom tags
  tags = var.tags
} 