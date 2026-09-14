# Nullify AWS Integration Terraform (AWS Provider v6)

This directory mirrors `../terraform/` but targets **AWS Terraform provider v6** (`~> 6.0`). Use this if your project has already upgraded to AWS provider v6.

For AWS provider v5, use `../terraform/` instead. `../terraform/README.md` documents the modules, variables and outputs; this file covers what differs.

## What Differs from v5

- **Per-resource `region`.** AWS provider v6 accepts a `region` argument on most resources and data sources. `nullify-aws-integration` reads each EKS cluster in the region from its ARN, so `eks_cluster_arns` can mix regions with one provider. There is no `eks_oidc_issuer_urls` variable here.
- **Ephemeral EKS token.** `examples/multi-cluster-complete` reads the cluster token with `ephemeral "aws_eks_cluster_auth"`, which keeps it out of plan and state and needs Terraform >= 1.10:

```hcl
ephemeral "aws_eks_cluster_auth" "primary" {
  region = "eu-west-1"
  name   = "..."
}
token = ephemeral.aws_eks_cluster_auth.primary.token
```

## Requirements

- Terraform >= 1.5 (>= 1.10 for `examples/multi-cluster-complete`)
- AWS provider ~> 6.0
- Kubernetes provider ~> 2.20 (only `modules/k8s-resources` and `examples/multi-cluster-complete`)

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
│   └── multi-cluster-complete/     # Two-cluster EKS example
├── versions.tf                     # AWS ~> 6.0
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
- `nullify_s3_access_point_arn`: S3 access point for collector uploads (optional)
- `kms_key_arn`: KMS key ARN or alias ARN from the Nullify configure page (optional); see "KMS" in `../terraform/README.md`
- `enable_kubernetes_integration`: Set to `true` for EKS integration
- `eks_cluster_arns`: List of EKS cluster ARNs to integrate with, in any region
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `service_account_name`: Collector service account name (default: nullify-k8s-collector-sa)
- `tags`: Resource tags
- `cronjob_schedule`: Deprecated and unused here; set the schedule on `k8s-resources`

`k8s-resources` defaults `collector_image` to `public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.45.0`. Replace any explicit `nullify/k8s-collector:latest`: Nullify does not publish that Docker Hub image.

## Validation

```bash
terraform fmt -recursive
terraform validate
terraform plan
```
