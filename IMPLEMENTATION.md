# Nullify AWS Integration - Implementation Guide

This guide is based on analysis of the real Nullify death-star-dast repository and provides production-ready templates for AWS integration.

## Key Findings from Nullify Death-Star-DAST Repository

### Configuration Values (Contact Nullify Support)
- **Nullify AWS Account ID**: `NULLIFY-ACCOUNT-ID` (provided by Nullify support)
- **Cross-account Role**: `NULLIFY-ROLE-NAME` (provided by Nullify support)
- **External IDs**: 
  - CloudFormation: `YOUR-CLOUDFORMATION-EXTERNAL-ID` (provided by Nullify support)
  - Terraform: `YOUR-TERRAFORM-EXTERNAL-ID` (provided by Nullify support)
- **Role Naming Convention**: `AWSIntegration-{CustomerName}-NullifyReadOnlyRole`
- **S3 Bucket**: `NULLIFY-S3-BUCKET` (provided by Nullify support)

### Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Your AWS      │    │  Nullify AWS    │    │  Kubernetes     │
│   Account       │    │  Account        │    │  Cluster        │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ IAM Role    │◄┼────┼─┤ Cross-Acc   │ │    │ │ CronJob     │ │
│ │ (ReadOnly)  │ │    │ │ Role        │ │    │ │ k8s-        │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ │ collector   │ │
│                 │    │                 │    │ └─────────────┘ │
│ ┌─────────────┐ │    │                 │    │ ┌─────────────┐ │
│ │ S3 Bucket   │ │    │                 │    │ │ IRSA        │ │
│ │ (Optional)  │ │    │                 │    │ │ ServiceAcc  │ │
│ └─────────────┘ │    │                 │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Implementation Options

### Option 1: Official Nullify Terraform Template (Recommended)

Use the **exact** Terraform template that Nullify provides:

```bash
cd terraform/
terraform init
terraform apply \
  -var="customer_name=mycompany" \
  -var="external_id=your-external-id-from-nullify"
```

**Features:**
- ✅ **Exact Nullify implementation** - matches their production setup
- ✅ Comprehensive AWS service permissions (500+ actions)
- ✅ Generic configuration (contact Nullify support for actual values)
- ✅ Production-ready security settings

### Option 2: Enhanced Terraform (More Features)

Use the enhanced Terraform templates for additional enterprise features:

```bash
cd terraform/
terraform apply \
  -var="customer_name=mycompany" \
  -var="external_id=your-external-id-from-nullify" \
  -var="create_s3_bucket=true"
```

**Features:**
- ✅ All official Nullify features
- ✅ Optional S3 bucket for integration artifacts
- ✅ Multi-environment support
- ✅ IRSA support for EKS
- ✅ Additional enterprise configurations

### Option 3: Standard Templates

Use the basic Terraform templates for a minimal setup:

```bash
cd terraform/
terraform apply -var="customer_name=mycompany" -var="external_id=your-external-id-from-nullify"
```

### Option 4: CloudFormation

Deploy using the **exact** Nullify CloudFormation template:

```bash
cd cloudformation/
aws cloudformation deploy \
  --template-file nullify-integration-role.yaml \
  --stack-name nullify-aws-integration \
  --parameter-overrides \
    CustomerName=mycompany \
    ExternalID=your-external-id-from-nullify \
  --capabilities CAPABILITY_NAMED_IAM
```

## Kubernetes Integration

### Using the Helm Chart

The Helm chart deploys a CronJob-based collector similar to the real k8s-collector:

```bash
# Add the repository
helm repo add nullify https://your-github-username.github.io/aws-integration-setup

# Install with real configuration
helm install nullify-aws-integration nullify/nullify-aws-integration \
  --set aws.roleArn="arn:aws:iam::YOUR-ACCOUNT:role/AWSIntegration-mycompany-NullifyReadOnlyRole" \
  --set aws.externalId="your-external-id" \
  --set nullify.apiToken="your-api-token" \
  --set nullify.organizationId="your-org-id" \
  --namespace nullify \
  --create-namespace
```

### IRSA Configuration

For EKS clusters, configure IAM Roles for Service Accounts:

```yaml
# values-eks.yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::YOUR-ACCOUNT:role/AWSIntegration-mycompany-NullifyReadOnlyRole

aws:
  region: "us-east-1"
  s3Bucket: "mycompany-nullify-k8s-collector"
  
collector:
  schedule: "0 0 * * *"  # Daily at midnight
  dataCollection:
    excludeNamespaces: "kube-system,kube-public"
    metadataOnly: true
```

## Production Deployment Checklist

### Pre-Deployment
- [ ] Obtain external ID from Nullify support
- [ ] Verify customer name matches Nullify's records
- [ ] Choose appropriate AWS region
- [ ] Review IAM permissions with security team

### AWS Infrastructure
- [ ] Deploy IAM role using enhanced templates
- [ ] Verify cross-account trust relationship
- [ ] Test role assumption from Nullify account
- [ ] (Optional) Create S3 bucket for artifacts

### Kubernetes Deployment
- [ ] Configure IRSA for EKS clusters
- [ ] Deploy Helm chart with production values
- [ ] Verify CronJob scheduling and execution
- [ ] Monitor logs for successful data collection

### Post-Deployment
- [ ] Verify data appears in Nullify dashboard
- [ ] Set up monitoring for failed jobs
- [ ] Configure alerting for permission issues
- [ ] Document role ARN for Nullify team

## Real-World Configuration Examples

### Enterprise Setup
```hcl
# terraform/terraform.tfvars
customer_name = "acmecorp"
environment = "prod"
aws_region = "us-east-1"
create_s3_bucket = true
external_id = "provided-by-nullify"

tags = {
  Owner = "SecurityTeam"
  CostCenter = "Infrastructure"
  Compliance = "SOC2"
}
```

### Multi-Environment Setup
```