# Nullify AWS Integration Module

This Terraform module creates the necessary AWS IAM roles and policies, plus optional Kubernetes resources for integrating with Nullify's security scanning platform.

## Features

- **IAM Role Creation**: Creates cross-account IAM role with comprehensive read-only permissions
- **Policy Management**: Manages multiple IAM policies (split due to size constraints)
- **S3 Integration**: Optional S3 access (only when needed)
- **Kubernetes Integration**: Optional Kubernetes resources for EKS
- **IRSA Support**: IAM Roles for Service Accounts (IRSA) integration for EKS
- **Security Best Practices**: Follows least-privilege principles

## Resources Created

### AWS Resources
- IAM Role with cross-account trust to Nullify's AWS account
- IAM Policies (3-4 separate policies):
  - Read-only access (Part 1 & 2) - Comprehensive AWS service permissions
  - S3 access policy - Limited write access to Nullify bucket (optional)
  - Deny policy - Explicitly denies sensitive operations
- Policy attachments

### Kubernetes Resources (Optional)
- Namespace (`nullify`)
- Service Account with IRSA annotation
- ClusterRole with read-only permissions
- ClusterRoleBinding
- CronJob for data collection

## Usage

```hcl
module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"
  
  # Required variables (provided by Nullify)
  customer_name    = "your-company"
  external_id      = "your-external-id-from-nullify"
  nullify_role_arn = "arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE-NAME"
  
  # Optional variables
  aws_region     = "us-east-1"
  s3_bucket_name = "your-nullify-bucket-name"  # Only if S3 integration needed
  
  # Optional Kubernetes integration
  enable_kubernetes_integration = true
  eks_oidc_id                  = "ABCDEF1234567890"
  
  tags = {
    Environment = "production"
    Team        = "security"
  }
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `customer_name` | `string` | - | **Required.** Customer name for resource naming |
| `external_id` | `string` | - | **Required.** External ID for cross-account access (provided by Nullify) |
| `nullify_role_arn` | `string` | - | **Required.** Nullify's cross-account role ARN (provided by Nullify) |
| `aws_region` | `string` | `"ap-southeast-2"` | AWS region for deployment |
| `s3_bucket_name` | `string` | `""` | S3 bucket for scan results (optional, only needed if S3 integration required) |
| `enable_kubernetes_integration` | `bool` | `false` | Enable Kubernetes resources |
| `eks_oidc_id` | `string` | `""` | EKS OIDC provider ID (required if Kubernetes integration enabled) |
| `kubernetes_namespace` | `string` | `"nullify"` | Kubernetes namespace name |
| `service_account_name` | `string` | `"nullify-k8s-collector-sa"` | Service account name |
| `cronjob_schedule` | `string` | `"0 0 * * *"` | CronJob schedule (daily at midnight) |
| `tags` | `map(string)` | `{"ManagedBy"="Terraform", "Purpose"="NullifyIntegration"}` | Resource tags |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the created IAM role |
| `role_name` | Name of the IAM role |
| `external_id` | External ID used (sensitive) |
| `s3_bucket_name` | S3 bucket name (null if not configured) |
| `policy_arns` | Map of all created policy ARNs |
| `kubernetes_namespace` | K8s namespace name (if enabled) |
| `kubernetes_service_account` | K8s service account name (if enabled) |
| `kubernetes_cluster_role` | K8s cluster role name (if enabled) |
| `kubernetes_cronjob` | K8s CronJob name (if enabled) |
| `deployment_summary` | Complete deployment summary |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | ~> 5.0 |
| kubernetes | ~> 2.20 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 5.0 |
| kubernetes | ~> 2.20 |

## Security Considerations

- **Cross-Account Access**: Uses external ID for additional security
- **Least Privilege**: Read-only permissions only
- **Optional S3**: S3 access only created when bucket name provided
- **Deny Policy**: Explicitly denies sensitive operations
- **IRSA Integration**: Secure token exchange for Kubernetes workloads

## License

This module is part of the Nullify AWS integration setup. 