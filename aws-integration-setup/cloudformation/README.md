# Nullify AWS Integration - CloudFormation Template

This directory contains a CloudFormation template for setting up AWS IAM roles and permissions required for Nullify's AWS integration.

## Overview

This template creates:
- IAM Role with cross-account trust to Nullify's AWS account
- Multiple IAM managed policies (split due to size limits)
- Support for both direct role assumption and EKS OIDC integration
- Comprehensive AWS service read permissions with security controls

## Prerequisites

1. **Contact Nullify Support** to obtain:
   - External ID for your account
   - Nullify's cross-account role ARN
   - S3 bucket name (for Kubernetes integration)

2. **AWS Requirements**:
   - AWS CLI configured with appropriate permissions
   - IAM permissions to create roles and policies

## Quick Start

### 1. Deploy via AWS Console

1. Download `nullify-cloudformation-template.json`
2. Go to CloudFormation console
3. Create new stack
4. Upload template file
5. Fill in parameters with values from Nullify support
6. Deploy stack

### 2. Deploy via AWS CLI

```bash
# Deploy the stack
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=S3BucketName,ParameterValue=NULLIFY-BUCKET \
  --capabilities CAPABILITY_NAMED_IAM

# Check deployment status
aws cloudformation describe-stacks \
  --stack-name nullify-aws-integration \
  --query 'Stacks[0].StackStatus'

# Get the role ARN
aws cloudformation describe-stacks \
  --stack-name nullify-aws-integration \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

### 3. Deploy with EKS Integration

```bash
# For EKS clusters, enable integration
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=S3BucketName,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=oidc.eks.us-east-1.amazonaws.com/id/YOUR-OIDC-ID \
  --capabilities CAPABILITY_NAMED_IAM
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `CustomerName` | String | Yes | Your company/customer identifier (1-10 chars) |
| `ExternalID` | String | Yes | External ID provided by Nullify support |
| `CrossAccountRoleArn` | String | Yes | Nullify's cross-account role ARN |
| `S3BucketName` | String | Yes | S3 bucket name for data collection (provided by Nullify support) |
| `AWSRegion` | String | No | AWS region (default: us-east-1) |
| `EnableEKSIntegration` | String | No | Enable EKS integration (default: false) |
| `EKSOidcProviderURL` | String | No* | EKS OIDC provider URL (*required if EKS enabled) |

## Resources Created

1. **IAMViewOnlyRole**: Main IAM role for Nullify integration
2. **ReadOnlyAccessPolicy**: Part 1 of AWS service permissions
3. **ReadOnlyAccessPolicy2**: Part 2 of AWS service permissions
4. **S3AccessPolicy**: S3 permissions for data collection
5. **DenyActionsPolicy**: Security controls to deny sensitive operations

## Outputs

- `RoleArn`: ARN of the created IAM role
- `RoleName`: Name of the created IAM role

## Security Features

### Access Controls
- **Cross-Account Trust**: Only trusts specified Nullify role ARN
- **External ID**: Prevents confused deputy attacks
- **Read-Only Permissions**: Comprehensive read access across AWS services
- **Deny Policy**: Explicitly denies sensitive operations like downloading container images

### EKS Integration
- **OIDC Provider**: Supports EKS service account integration
- **Conditional Logic**: EKS resources only created when enabled
- **Service Account Trust**: Specific trust for `nullify:nullify-k8s-collector-sa`

## Troubleshooting

### Common Issues

1. **Stack Creation Failed - Customer Name Invalid**
   ```
   Error: Customer name must start with a letter and can only contain letters, numbers, underscores, and hyphens
   ```
   **Solution**: Use only alphanumeric characters, underscores, and hyphens (1-10 characters)

2. **Stack Creation Failed - OIDC Provider Not Found**
   ```
   Error: Invalid identity provider
   ```
   **Solution**: Ensure EKS cluster has OIDC provider enabled and URL is correct

3. **External ID Mismatch**
   ```
   Error: Access denied during role assumption
   ```
   **Solution**: Verify external ID with Nullify support

## Next Steps

1. ✅ Note the role ARN from stack outputs
2. ✅ Provide role ARN to Nullify support team
3. ✅ Verify integration in Nullify dashboard
4. ✅ Monitor CloudTrail for role assumption events 