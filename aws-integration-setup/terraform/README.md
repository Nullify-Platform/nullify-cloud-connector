# Nullify AWS Integration Terraform

This Terraform configuration uses a module to create the necessary AWS IAM roles and policies, plus optional Kubernetes resources for integrating with Nullify's security scanning platform.

## Architecture

This configuration is organized as a Terraform module with a clean separation between the reusable module and the root configuration:

```
terraform/
├── modules/
│   └── nullify-aws-integration/    # Reusable module
│       ├── versions.tf             # Module provider requirements
│       ├── variables.tf            # Module input variables
│       ├── locals.tf               # Module local values
│       ├── data.tf                 # Data sources and policies
│       ├── main.tf                 # Core IAM resources
│       ├── kubernetes.tf           # Kubernetes resources
│       ├── outputs.tf              # Module outputs
│       └── README.md               # Module documentation
├── examples/
│   ├── basic/                      # AWS IAM only example
│   └── with-kubernetes/            # Full EKS integration example
├── versions.tf                     # Root provider requirements
├── providers.tf                    # Root provider configurations
├── variables.tf                    # Root input variables
├── main.tf                         # Module instantiation
├── outputs.tf                      # Root outputs (from module)
├── terraform.tfvars.example        # Example configuration
└── README.md                       # This file
```

## Examples

Two complete examples are provided:

### **Basic Example** (`examples/basic/`)
- AWS IAM resources only
- No Kubernetes integration
- Minimal configuration

### **With-Kubernetes Example** (`examples/with-kubernetes/`)
- Full AWS IAM + EKS integration
- Kubernetes resources and IRSA setup
- Complete EKS cluster integration

Both examples reference the shared `terraform.tfvars.example` from the root directory.

## Benefits of Module Structure

- **Reusability**: The module can be used across multiple environments
- **Encapsulation**: Clean separation of concerns
- **Versioning**: Module can be versioned and published
- **Testing**: Module can be tested independently
- **Maintainability**: Easier to maintain and update

## Quick Start

1. **Copy the example configuration:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars`** with your specific values:
   ```hcl
   customer_name = "your-company-name"
   # Add other required variables
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan
   ```

5. **Apply the configuration:**
   ```bash
   terraform apply
   ```

## Module Usage

The root configuration instantiates the `nullify-aws-integration` module:

```hcl
module "nullify_aws_integration" {
  source = "./modules/nullify-aws-integration"
  
  customer_name                 = var.customer_name
  external_id                   = var.external_id
  nullify_role_arn              = var.nullify_role_arn
  enable_kubernetes_integration = var.enable_kubernetes_integration
  eks_oidc_id                  = var.eks_oidc_id
  # ... other variables
}
```

## Required Variables

- `customer_name`: Your company/customer name (used in resource naming)
- `external_id`: External ID for cross-account access (provided by Nullify)
- `nullify_role_arn`: Nullify's cross-account role ARN (provided by Nullify)

## Optional Variables

- `aws_region`: AWS region for deployment (default: ap-southeast-2)
- `s3_bucket_name`: S3 bucket for scan results (only needed if S3 integration required)
- `enable_kubernetes_integration`: Enable Kubernetes resources (default: false)
- `eks_oidc_id`: EKS OIDC provider ID (required if Kubernetes enabled)
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `service_account_name`: Kubernetes service account name (default: nullify-k8s-collector-sa)
- `cronjob_schedule`: Cron schedule for data collection (default: "0 0 * * *")
- `tags`: Resource tags (default: ManagedBy=Terraform, Purpose=NullifyIntegration)

## S3 Integration

S3 integration is optional. If you don't provide an `s3_bucket_name`, the S3 access policy will not be created. This makes the integration more flexible for environments that don't require S3 access.

## Kubernetes Integration

To enable Kubernetes integration:

1. Set `enable_kubernetes_integration = true`
2. Provide your EKS cluster's OIDC provider ID in `eks_oidc_id`
3. Configure the Kubernetes provider in `providers.tf`

## Outputs

The configuration provides several outputs from the module:

- `role_arn`: ARN of the created IAM role
- `deployment_summary`: Complete deployment information
- Kubernetes resource names (when enabled)

## Using the Module in Other Projects

You can use this module in other Terraform projects by referencing it:

```hcl
module "nullify_integration" {
  source = "git::https://github.com/your-org/nullify-terraform.git//terraform/modules/nullify-aws-integration?ref=v1.0.0"
  
  customer_name = "my-company"
  aws_region    = "us-west-2"
  # ... other variables
}
```

## Validation

To validate your configuration:

```bash
# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Check what will be created
terraform plan
```

## Security Considerations

- The external ID acts as an additional security layer for cross-account access
- The IAM role has comprehensive read-only permissions as required by Nullify
- Kubernetes resources use least-privilege RBAC
- All sensitive outputs are marked as sensitive

## Module Development

To modify the module:

1. Make changes in `modules/nullify-aws-integration/`
2. Test the module independently
3. Update version tags for releases
4. Update documentation as needed

## Support

For questions about this Terraform configuration:
- Check the [module documentation](./modules/nullify-aws-integration/README.md)
- Refer to Nullify documentation
- Contact Nullify support 