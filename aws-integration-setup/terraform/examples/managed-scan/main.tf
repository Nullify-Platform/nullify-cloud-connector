# Managed EKS scan: Nullify lists Kubernetes resources from its own compute
# through an EKS access entry. Nothing runs in the cluster.

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.33"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

locals {
  cluster_name   = split("/", var.eks_cluster_arn)[1]
  cluster_region = split(":", var.eks_cluster_arn)[3]
}

provider "aws" {
  region = local.cluster_region
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

module "nullify_aws_integration" {
  source           = "../../modules/nullify-aws-integration"
  customer_name    = var.customer_name
  external_id      = var.external_id
  nullify_role_arn = var.nullify_role_arn
  aws_region       = local.cluster_region
  tags             = var.tags
}

module "eks_managed_scan_access" {
  source                = "../../modules/eks-managed-scan-access"
  principal_arn         = module.nullify_aws_integration.role_arn
  principal_unique_id   = module.nullify_aws_integration.role_unique_id
  cluster_arns          = [var.eks_cluster_arn]
  nullify_region        = var.nullify_region
  authorization         = var.authorization
  kubernetes_group_name = var.kubernetes_group_name
  tags                  = var.tags
}

# Creating the ClusterRole needs rights to grant every permission in it, which
# in practice means cluster-admin. Set manage_rbac = false when Helm, Flux or
# Argo CD applies the nullify-readonly ClusterRole instead.
module "k8s_resources" {
  source = "../../modules/k8s-resources"
  count  = var.manage_rbac ? 1 : 0

  enable_collector              = false
  enable_managed_scan_rbac      = true
  managed_scan_kubernetes_group = var.kubernetes_group_name
}
