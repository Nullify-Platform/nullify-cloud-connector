# Nullify AWS Integration Terraform (AWS Provider v6)

This directory mirrors `../terraform/` but targets **AWS Terraform provider v6** (`~> 6.0`). Use this if your project has already upgraded to AWS provider v6.

For AWS provider v5, use `../terraform/` instead.

## What Changed from v5

The only breaking change that affects this configuration:

**`data "aws_eks_cluster_auth"` was removed in AWS provider v6.** It is replaced by the `ephemeral` resource variant, which requires Terraform >= 1.10:

```hcl
# v5 (removed in v6)
data "aws_eks_cluster_auth" "primary" {
  name = "..."
}
token = data.aws_eks_cluster_auth.primary.token

# v6
ephemeral "aws_eks_cluster_auth" "primary" {
  name = "..."
}
token = ephemeral.aws_eks_cluster_auth.primary.token
```

This change is applied in `examples/multi-cluster-complete/main.tf`. The core `nullify-aws-integration` module and `k8s-resources` module are unaffected.

## Requirements

- Terraform >= 1.10 (for ephemeral resource support in the multi-cluster example)
- AWS provider ~> 6.0
- Kubernetes provider ~> 2.20

## Architecture

```
terraform-v6/
├── modules/
│   ├── nullify-aws-integration/    # AWS IAM resources only
│   │   ├── versions.tf             # AWS provider ~> 6.0
│   │   ├── variables.tf
│   │   ├── locals.tf
│   │   ├── data.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   └── k8s-resources/              # Kubernetes resources only
│       ├── providers.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
├── examples/
│   ├── basic/                      # AWS IAM only example
│   └── multi-cluster-complete/     # Full multi-cluster EKS example
├── versions.tf                     # AWS ~> 6.0, Kubernetes ~> 2.20
├── variables.tf
├── main.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars.example
└── README.md
```

## Quick Start

### 1. AWS-Only Integration

```bash
cd examples/basic/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

### 2. Multi-Cluster EKS Integration

```bash
cd examples/multi-cluster-complete/
cp terraform.tfvars.example terraform.tfvars
# Edit with your cluster ARNs and values
terraform init && terraform apply
```

## Required Variables

- `customer_name`: Your company/customer name (used in resource naming)
- `external_id`: External ID for cross-account access (provided by Nullify configure page)
- `nullify_role_arn`: Nullify's cross-account role ARN (provided by Nullify configure page)

## Optional Variables

- `aws_region`: AWS region for IAM resources (default: ap-southeast-2)
- `s3_bucket_name`: S3 bucket for scan results (optional)
- `kms_key_arn`: KMS key ARN for key management operations (optional)
- `enable_kubernetes_integration`: Set to `true` for EKS integration
- `eks_cluster_arns`: List of EKS cluster ARNs to integrate with
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `cronjob_schedule`: Cron schedule for data collection (default: "0 0 * * *")
- `collector_image`: Docker image for collector (default: nullify/k8s-collector:latest)
- `tags`: Resource tags

## Validation

```bash
terraform fmt -recursive
terraform validate
terraform plan
```
