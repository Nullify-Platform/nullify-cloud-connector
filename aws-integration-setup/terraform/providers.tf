# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Kubernetes Provider - configured for use with EKS
provider "kubernetes" {
  # To use this provider, you need to configure it with your EKS cluster details
  # Uncomment and configure the following lines for your specific EKS cluster:

  # host                   = data.aws_eks_cluster.cluster.endpoint
  # cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  # token                  = data.aws_eks_cluster_auth.cluster.token

  # Or alternatively, use the AWS CLI configuration:
  # config_path    = "~/.kube/config"
  # config_context = "your-eks-context"
}

# Uncomment these data sources if using the EKS cluster configuration above
# data "aws_eks_cluster" "cluster" {
#   name = var.eks_cluster_name
# }
# 
# data "aws_eks_cluster_auth" "cluster" {
#   name = var.eks_cluster_name
# } 