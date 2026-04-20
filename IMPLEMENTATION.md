# Nullify Cloud Connector - Implementation Guide

Production-ready templates for integrating Nullify's security platform with AWS and GCP environments.

### Configuration Values (from Nullify Console)
- **Nullify Role ARN**: Provided in the Nullify configure page
- **External ID**: Provided in the Nullify configure page
- **S3 Bucket**: Provided in the Nullify configure page
- **KMS Key ARN**: Provided in the Nullify configure page

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

Deploy using the Nullify CloudFormation template:

```bash
cd aws-integration-setup/cloudformation/
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=mycompany \
    ParameterKey=ExternalID,ParameterValue=your-external-id-from-nullify \
  --capabilities CAPABILITY_NAMED_IAM
```

## Kubernetes Integration

### Using the Helm Chart

The Helm chart deploys a CronJob-based collector similar to the real k8s-collector:

```bash
# Add the repository
helm repo add nullify https://nullify-platform.github.io/nullify-cloud-connector/
helm repo update

# Install with a values file (recommended)
helm install nullify-collector nullify/nullify-k8s-collector \
  -f values-production.yaml \
  --namespace nullify \
  --create-namespace
```

See the [chart README](helm-charts/nullify-k8s-collector/README.md) for all configuration options and per-platform (EKS / GKE) onboarding steps.

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