# Nullify AWS Integration Terraform

This Terraform configuration provides modular components for integrating with Nullify's security scanning platform, supporting both AWS-only and full EKS cluster integrations.

This directory targets AWS provider v5. If your project uses AWS provider v6, use `../terraform-v6/`.

## ⚠️ Important Notice

**EKS Integration**: The AWS integration module only sets up IAM roles and trust policies. For full EKS integration, you must also deploy the Kubernetes resources using the separate `k8s-resources` module or Helm charts.

## Requirements

- Terraform >= 1.5
- AWS provider `~> 5.0`
- Kubernetes provider `~> 2.20` (only `modules/k8s-resources` and `examples/multi-cluster-complete`)

## Architecture

The configuration is organized into separate, focused modules:

```
terraform/
├── modules/
│   ├── nullify-aws-integration/    # AWS IAM resources only
│   │   ├── versions.tf             # AWS provider requirements
│   │   ├── variables.tf            # Module input variables
│   │   ├── locals.tf               # Module local values
│   │   ├── data.tf                 # Data sources and policies
│   │   ├── main.tf                 # Core IAM resources
│   │   └── outputs.tf              # Module outputs
│   └── k8s-resources/              # Kubernetes resources only
│       ├── providers.tf            # Kubernetes provider requirements
│       ├── variables.tf            # Module input variables
│       ├── main.tf                 # Kubernetes resources
│       └── outputs.tf              # Module outputs
├── examples/
│   ├── basic/                      # AWS IAM only example
│   └── multi-cluster-complete/     # Two-cluster EKS example
├── versions.tf                     # Root provider requirements
├── providers.tf                    # AWS provider
├── variables.tf                    # Root input variables
├── main.tf                         # Module instantiation
├── outputs.tf                      # Root outputs
├── terraform.tfvars.example        # Example configuration
└── README.md                       # This file
```

## Module Separation Benefits

- **AWS Module**: Creates IAM roles with multi-cluster OIDC trust policies
- **K8s Module**: Deploys collector cronjob and RBAC to any cluster
- **Independent Deployment**: Deploy AWS resources once, K8s resources per cluster
- **Multi-Region Support**: Region taken from each cluster ARN
- **Simplified Management**: Each module has focused responsibilities

## Examples

### **Basic Example** (`examples/basic/`)
- AWS IAM resources only
- No Kubernetes integration
- Minimal configuration for cloud-only scanning

### **Multi-Cluster Complete** (`examples/multi-cluster-complete/`)
- Full AWS IAM + EKS integration for exactly two clusters
- Clusters can be in different regions: each is read through an AWS provider in its own region
- Automatic OIDC provider discovery

## Multi-Cluster Support

One IAM role can trust the collector on several clusters:

```hcl
eks_cluster_arns = [
  "arn:aws:eks:us-west-2:123456789012:cluster/prod-cluster",
  "arn:aws:eks:us-west-2:123456789012:cluster/staging-cluster"
]
```

AWS provider v5 can only look an EKS cluster up in the provider's own region. The module therefore fails at plan time if a cluster is outside that region, unless you pass `eks_oidc_issuer_urls` (one per cluster, same order):

```hcl
eks_cluster_arns = [
  "arn:aws:eks:us-west-2:123456789012:cluster/prod-cluster",
  "arn:aws:eks:eu-west-1:123456789012:cluster/eu-cluster"
]
eks_oidc_issuer_urls = [
  "https://oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE1111111111111111111111111",
  "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE2222222222222222222222222"
]
```

Get an issuer with `aws eks describe-cluster --region <region> --name <name> --query cluster.identity.oidc.issuer --output text`, or read it through a regional provider as `examples/multi-cluster-complete` does. `../terraform-v6/` looks every cluster up in its own region without this variable.

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

## EKS Integration Variables

- `enable_kubernetes_integration`: Set to `true` to trust the in-cluster collector's service account
- `eks_cluster_arns`: List of EKS cluster ARNs to integrate with
- `eks_oidc_issuer_urls`: OIDC issuer per cluster, only needed for clusters outside `aws_region`

## Optional Variables

- `aws_region`: AWS region for IAM resources (default: ap-southeast-2)
- `s3_bucket_name`: S3 bucket for scan results (optional)
- `nullify_s3_access_point_arn`: S3 access point for collector uploads (optional). Grants `s3:PutObject` and `s3:PutObjectAcl` on `<access point ARN>/object/k8s-collector/*` next to the bucket grants
- `kms_key_arn`: KMS ARN from the Nullify configure page (optional), see [KMS](#kms)
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `service_account_name`: Collector service account name (default: nullify-k8s-collector-sa)
- `tags`: Resource tags
- `cronjob_schedule`: Deprecated and unused here; set the schedule on `k8s-resources`

## KMS

`kms_key_arn` accepts either form shown on the Nullify configure page:

- a key ARN: `arn:aws:kms:<region>:<account>:key/<key-id>`, including multi-Region `key/mrk-...` keys
- an alias ARN: `arn:aws:kms:<region>:<account>:alias/<name>`

IAM ignores alias ARNs in a policy's `Resource`, so the KMS policy grants the ARN you pass and `arn:aws:kms:<region>:<account>:key/*` in the same Nullify account and region. Nullify's key policy is the real gate: the role can only use Nullify keys whose key policy allows it. The `kms_policy_resources` module output lists both resources.

## Module Usage

### AWS Integration Only
```hcl
module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"

  customer_name    = "your-company"
  external_id      = "your-external-id"
  nullify_role_arn = "arn:aws:iam::NULLIFY-ACCOUNT:role/role-name"

  # Optional configurations
  kms_key_arn    = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  s3_bucket_name = "your-scan-results-bucket"

  # Optional EKS integration
  enable_kubernetes_integration = true
  eks_cluster_arns = [
    "arn:aws:eks:us-west-2:123456789012:cluster/my-cluster"
  ]
}
```

### Kubernetes Resources (Deploy per Cluster)
```hcl
module "k8s_resources" {
  source = "./modules/k8s-resources"

  providers = {
    kubernetes = kubernetes.cluster_a
  }

  iam_role_arn   = module.nullify_aws_integration.role_arn
  s3_bucket_name = "my-scan-results-bucket" # or the S3 access point ARN from Nullify
  kms_key_arn    = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  aws_region     = "us-west-2"
  enable_debug   = false
}
```

`k8s-resources` variables include `collector_image`, `cronjob_schedule` (default `0 0 * * *`), `kubernetes_namespace`, `service_account_name` and `enable_debug`.

`collector_image` defaults to `public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.45.0`, a pinned tag of Nullify's ECR Public image. Earlier versions defaulted to `nullify/k8s-collector:latest` on Docker Hub, which Nullify does not publish; if you set that value explicitly, replace it.

## Outputs

### AWS Integration Module
- `role_arn`: ARN of the created IAM role
- `deployment_summary`: Complete deployment information
- `cluster_integration_summary`: Multi-cluster setup details
- `all_oidc_ids`: List of OIDC provider IDs
- `kms_policy_resources`: Resources granted by the KMS policy

### K8s Resources Module
- `namespace_name`: Created namespace name
- `service_account_name`: Service account name
- `cluster_role_name`, `cluster_role_binding_name`: Collector RBAC names
- `cronjob_name`: Data collector cronjob name

## Using Modules in Other Projects

Reference the modules from this repository, pinned to a release tag:

```hcl
module "nullify_aws" {
  source = "git::https://github.com/Nullify-Platform/nullify-cloud-connector.git//aws-integration-setup/terraform/modules/nullify-aws-integration?ref=<tag>"

  customer_name = "my-company"
  external_id   = var.external_id
  # ... other variables
}

module "nullify_k8s" {
  source = "git::https://github.com/Nullify-Platform/nullify-cloud-connector.git//aws-integration-setup/terraform/modules/k8s-resources?ref=<tag>"

  iam_role_arn = module.nullify_aws.role_arn
  # ... other variables
}
```

## Upgrade Notes

- Terraform >= 1.5 is now required (the module already used cross-variable validation, which needs 1.9; those checks are now preconditions).
- The root configuration no longer declares the Kubernetes provider. It never deployed Kubernetes resources.
- A cluster outside the AWS provider's region now fails at plan time with an explanation instead of a not-found error.
- The KMS policy now also grants `key/*` in the account and region of `kms_key_arn`.

## Security Considerations

- External ID provides additional cross-account security
- IAM role has comprehensive read-only permissions
- Kubernetes resources use least-privilege RBAC
- Supports multiple clusters without compromising security
- IRSA (IAM Roles for Service Accounts) for secure pod authentication

## Validation

```bash
# Format and validate
terraform fmt -recursive
terraform validate

# Plan deployment
terraform plan

# Check security
terraform show -json | jq '.values.root_module.resources[].values'
```

## Support

- Example configurations: `./examples/*/`
- Contact Nullify support for integration assistance
