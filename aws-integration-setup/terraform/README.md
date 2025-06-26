# Nullify AWS Integration Terraform

This Terraform configuration provides modular components for integrating with Nullify's security scanning platform, supporting both AWS-only and full EKS cluster integrations.

## ⚠️ Important Notice

**EKS Integration**: The AWS integration module only sets up IAM roles and trust policies. For full EKS integration, you must also deploy the Kubernetes resources using the separate `k8s-resources` module or Helm charts.

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
│       ├── versions.tf             # Kubernetes provider requirements
│       ├── variables.tf            # Module input variables
│       ├── main.tf                 # Kubernetes resources
│       └── outputs.tf              # Module outputs
├── examples/
│   ├── basic/                      # AWS IAM only example
│   └── multi-cluster-complete/     # Full multi-cluster EKS example
├── versions.tf                     # Root provider requirements
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
- **Multi-Region Support**: Automatic region detection from cluster ARNs
- **Simplified Management**: Each module has focused responsibilities

## Examples

### **Basic Example** (`examples/basic/`)
- AWS IAM resources only
- No Kubernetes integration
- Minimal configuration for cloud-only scanning

### **Multi-Cluster Complete** (`examples/multi-cluster-complete/`)
- Full AWS IAM + multi-cluster EKS integration  
- Supports clusters from different regions
- Automatic OIDC provider discovery
- Single deployment handles multiple clusters

## Multi-Cluster Support

The architecture now supports multiple EKS clusters seamlessly:

```hcl
# Supports clusters from different regions
eks_cluster_arns = [
  "arn:aws:eks:us-west-2:123456789012:cluster/prod-cluster",
  "arn:aws:eks:eu-west-1:123456789012:cluster/eu-cluster",
  "arn:aws:eks:us-west-2:123456789012:cluster/staging-cluster"
]
```

**Features:**
- Automatic region extraction from cluster ARNs
- Dynamic OIDC provider discovery 
- Multi-region trust policy generation
- Single IAM role trusts all specified clusters

## Quick Start

### 1. AWS-Only Integration

```bash
cd examples/basic/
cp ../../terraform.tfvars.example terraform.tfvars
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

- `eks_cluster_arns`: List of EKS cluster ARNs to integrate with
- `enable_kubernetes_integration`: Set to `true` for EKS integration

## Optional Variables

- `aws_region`: AWS region for IAM resources (default: ap-southeast-2)
- `s3_bucket_name`: S3 bucket for scan results (optional)
- `kms_key_arn`: KMS key ARN for key management operations (optional, provided by Nullify configure page if needed)
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `cronjob_schedule`: Cron schedule for data collection (default: "0 0 * * *")
- `collector_image`: Docker image for collector (default: nullify/k8s-collector:latest)
- `tags`: Resource tags

## Module Usage

### AWS Integration Only
```hcl
module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"
  
  customer_name    = "your-company"
  external_id      = "your-external-id"
  nullify_role_arn = "arn:aws:iam::NULLIFY-ACCOUNT:role/role-name"
  
  # Optional configurations
  kms_key_arn    = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"  # Optional
  s3_bucket_name = "your-scan-results-bucket"  # Optional
  
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
  s3_bucket_name = "my-scan-results-bucket"
  kms_key_arn    = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"  # Optional
  aws_region     = "us-west-2"
}
```

## Outputs

### AWS Integration Module
- `role_arn`: ARN of the created IAM role
- `deployment_summary`: Complete deployment information
- `cluster_integration_summary`: Multi-cluster setup details
- `all_oidc_ids`: List of OIDC provider IDs

### K8s Resources Module  
- `namespace_name`: Created namespace name
- `service_account_name`: Service account name
- `cronjob_name`: Data collector cronjob name

## Using Modules in Other Projects

Reference the modules in other Terraform projects:

```hcl
module "nullify_aws" {
  source = "git::https://github.com/your-org/nullify-terraform.git//terraform/modules/nullify-aws-integration?ref=v1.0.0"
  
  customer_name = "my-company"
  external_id   = var.external_id
  # ... other variables
}

module "nullify_k8s" {
  source = "git::https://github.com/your-org/nullify-terraform.git//terraform/modules/k8s-resources?ref=v1.0.0"
  
  iam_role_arn = module.nullify_aws.role_arn
  # ... other variables
}
```

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

- Module documentation: `./modules/*/README.md`
- Example configurations: `./examples/*/`
- Contact Nullify support for integration assistance
