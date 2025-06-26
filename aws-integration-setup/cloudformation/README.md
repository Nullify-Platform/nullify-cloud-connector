# Nullify AWS Integration - CloudFormation Template

This directory contains a CloudFormation template for setting up AWS IAM roles and permissions required for Nullify's AWS integration.

## ⚠️ Important Notice

**EKS Integration**: The EKS integration created by this CloudFormation template only sets up the necessary IAM roles and trust policies. For the integration to be fully functional, you must deploy the Kubernetes cronjob resources separately using Helm charts or other Kubernetes deployment methods. The CloudFormation template alone does not deploy any Kubernetes resources.

## Overview

This template creates:
- IAM Role with cross-account trust to Nullify's AWS account
- Multiple IAM managed policies (split due to size limits)
- Support for both direct role assumption and EKS OIDC integration
- Comprehensive AWS service read permissions with security controls

## Prerequisites

1. **Obtain Configuration Values from Nullify Configure Page**:
   - Log in to your Nullify configure page
   - Navigate to Configure > Integrations
   - Select AWS integration to begin setup
   - Note the provided values:
     - External ID for your account
     - Nullify's cross-account role ARN
     - S3 bucket name (for Kubernetes integration)
     - KMS key ARN (optional, for key management operations)

2. **AWS Requirements**:
   - AWS CLI configured with appropriate permissions
   - IAM permissions to create roles and policies

3. **For EKS Integration** (optional):
   - EKS cluster with OIDC provider enabled
   - OIDC provider URL (see [Getting EKS OIDC URL](#getting-eks-oidc-url) below)
   - **Helm charts or Kubernetes manifests** to deploy the collector cronjobs

> 📖 **Reference**: For detailed setup instructions, see the [Nullify AWS Integration Documentation](https://docs.nullify.ai/integrations/aws/configuration).

**Alternative**: Contact Nullify Support for assistance with configuration values.

## Getting EKS OIDC URL

If you're enabling EKS integration, you'll need the OIDC provider URL from your EKS cluster.

### Method 1: AWS CLI (Recommended)
```bash
# Get OIDC URL for your cluster
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text

# Remove the https:// prefix for the CloudFormation parameter
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||'
```

**Example output:**
```
https://oidc.eks.us-west-2.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890
```

**For CloudFormation parameter (without https://):**
```
oidc.eks.us-west-2.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890
```

### Method 2: AWS Console
1. Go to **Amazon EKS** in the AWS Console
2. Click on your cluster name
3. Go to the **Configuration** tab
4. Under **Details**, look for **OpenID Connect provider URL**

### Method 3: kubectl (if you have cluster access)
```bash
kubectl get configmap aws-auth -n kube-system -o yaml | grep "oidc"
```

### OIDC URL Format
- **Full URL format**: `https://oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID`
- **For CloudFormation parameter**: Use only the part **after** `https://`
- **Example**: If full URL is `https://oidc.eks.us-west-2.amazonaws.com/id/ABC123`, use `oidc.eks.us-west-2.amazonaws.com/id/ABC123`

### Enabling OIDC on EKS (if not already enabled)
```bash
# Check if OIDC is enabled
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc'

# If null, enable OIDC provider
eksctl utils associate-iam-oidc-provider --cluster YOUR_CLUSTER_NAME --approve
```

## Quick Start

### 1. Deploy via AWS Console

1. Download `nullify-cloudformation-template.json`
2. Go to CloudFormation console
3. Create new stack
4. Upload template file
5. Fill in parameters with values from Nullify configure page
6. Deploy stack

### 2. Deploy via AWS CLI

```bash
# Deploy the stack
# Note: ExternalID, CrossAccountRoleArn, and NullifyS3Bucket values are provided in the Nullify configure page
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
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
# First, get your OIDC URL (see "Getting EKS OIDC URL" section above)
# Note: ExternalID, CrossAccountRoleArn, and NullifyS3Bucket values are provided in the Nullify configure page
OIDC_URL=$(aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')

aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=$OIDC_URL \
  --capabilities CAPABILITY_NAMED_IAM

# Or manually with a specific OIDC URL:
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=A78D8794A06CAE5791C5812CDB164C7D.gr7.ap-southeast-2.eks.amazonaws.com \
  --capabilities CAPABILITY_NAMED_IAM
```

### 4. Deploy with KMS Integration (Optional)

```bash
# Deploy with KMS key ARN for key management operations
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=NullifyKMSKeyArn,ParameterValue=arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012 \
  --capabilities CAPABILITY_NAMED_IAM
```