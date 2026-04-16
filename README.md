# 🛡️ Nullify Cloud Connector - Infrastructure Templates

**Complete infrastructure templates for deploying Nullify's cloud security integrations across Kubernetes and AWS.**

> 🚨 **SECURITY NOTICE**: This repository contains **GENERIC TEMPLATES ONLY**. Contact Nullify support for production configuration values.

## 🎯 **Overview**

This repository provides comprehensive infrastructure-as-code templates for integrating Nullify's security platform with your cloud environment. It includes multiple deployment options to suit different infrastructure preferences and requirements.

### **What's Included**
- ⚙️ **Helm Charts** - Production-ready Kubernetes deployment for **EKS (IRSA)** and **GKE (Workload Identity)**
- 🏗️ **CloudFormation Templates** - AWS infrastructure setup with IAM roles and policies
- 🔧 **Terraform Modules** - Modular infrastructure-as-code for AWS and multi-cluster EKS integration
- ☁️ **GCP Terraform** - Read-only GCP integration via Workload Identity Federation
- 🤖 **GitHub Actions** - Automated chart publishing and validation
- 📚 **Documentation** - Comprehensive setup and security guides
- ❌ **NO real sensitive data, bucket names, or account IDs**

### **Use Cases**
- **Kubernetes Security Scanning** - Deploy collectors to gather cluster metadata
- **AWS Account Integration** - Set up cross-account access for security assessments  
- **Multi-Cloud Deployments** - Consistent infrastructure across environments
- **Multi-Cluster Support** - Integrate multiple EKS clusters across regions
- **GitOps Workflows** - Automated deployment and updates via CI/CD

### **Deployment Options**
1. **Helm Charts** (`helm-charts/`) - For Kubernetes-native deployments
2. **CloudFormation** (`aws-integration-setup/cloudformation/`) - For AWS-centric infrastructure
3. **Terraform** (`aws-integration-setup/terraform/`) - For infrastructure-as-code workflows with modular architecture
4. **GCP Terraform** (`gcp-integration-setup/terraform/`) - For Google Cloud read-only integration via Workload Identity Federation
5. **GKE Collector Terraform** (`gcp-integration-setup/terraform/modules/nullify-gke-collector/`) - For deploying the k8s-collector on GKE clusters

## 🚀 **Quick Start**

### **Choose Your Deployment Method**

| Method | Best For | Prerequisites |
|--------|----------|---------------|
| **🎯 Helm Charts** | Kubernetes-native teams, GitOps workflows | EKS or GKE cluster, Helm 3.x, kubectl |
| **🏗️ CloudFormation** | AWS-centric infrastructure, ClickOps teams | AWS CLI, appropriate IAM permissions |
| **🔧 Terraform (AWS)** | Infrastructure-as-code, multi-cluster teams | Terraform, AWS provider configured |
| **☁️ Terraform (GCP)** | GCP environments, Workload Identity Federation | Terraform, `gcloud` auth on the host project, org or folder admin access |
| **☁️ Terraform (GKE collector)** | GKE clusters running the Nullify k8s-collector | Terraform, GKE with Workload Identity enabled |

### **GCP Quick Start**

The GCP integration uses Workload Identity Federation only — no long-lived service account JSON keys are minted.

```bash
cd gcp-integration-setup/terraform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars            # paste values from the Nullify console
terraform init && terraform apply
```

Then paste the `service_account_email` and `workload_identity_provider` outputs into the Nullify console under **Settings → Cloud Integrations → GCP** and click **Verify**.

See [`gcp-integration-setup/terraform/README.md`](gcp-integration-setup/terraform/README.md) for the full guide, the org / folder / project scope options, and the gcloud-only installer.

### **Prerequisites (All Methods)**

1. **AWS Account** with appropriate permissions
2. **Nullify Account** and dashboard access
3. **Kubernetes cluster** for Helm deployments — **EKS** (IRSA) or **GKE** (Workload Identity). See the [chart README](helm-charts/nullify-k8s-collector/README.md#supported-platforms) for per-platform onboarding steps.

**Obtain Configuration Values from Nullify Configure Page:**

1. **Log in to your Nullify configure page**
2. **Navigate to Configure > Integrations**
3. **Select AWS integration** to begin setup
4. **Note the provided values:**
   - **Nullify Role ARN**: The ARN of Nullify's cross-account role
   - **External ID**: Unique identifier for secure cross-account access
   - **S3 Bucket Name**: For secure data transfer
   - **KMS Key ARN**: For encryption operations

> 📖 **Reference**: For detailed setup instructions, see the [Nullify AWS Integration Documentation](https://docs.nullify.ai/integrations/aws/configuration).

**Alternative**: Contact Nullify Support for assistance with configuration values.

---

## ⚙️ **Helm Chart Deployment**

### **Option 1: Install from Helm Repository (Recommended)**

```bash
# 1. Add the Nullify Helm repository
helm repo add nullify https://nullify-platform.github.io/nullify-cloud-connector/
helm repo update

# 2. Create your production values file (get values from Nullify configure page)
cat > values-production.yaml << EOF
collector:
  aws:
    region: "us-west-2"                # Extract from your KMS key ARN
  clusterName: "your-cluster-name"     # Must match your actual EKS cluster name
  s3:
    bucket: "your-nullify-bucket"
  kms:
    keyArn: "arn:aws:kms:us-west-2:123456789012:key/your-key-id"

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/NullifyReadOnlyRole"
EOF

# 3. Install the chart
helm install nullify-collector nullify/nullify-k8s-collector \
  -f values-production.yaml \
  --namespace nullify \
  --create-namespace

# 4. Verify deployment
kubectl get all -n nullify
```

### **Option 2: Install from Source**

```bash
# 1. Clone this repository
git clone https://github.com/Nullify-Platform/nullify-cloud-connector.git
cd nullify-cloud-connector

# 2. Create your production values file
cp helm-charts/nullify-k8s-collector/values-example.yaml values-production.yaml

# 3. Edit with your actual values (provided by Nullify configure page)
vi values-production.yaml

# 4. Install the chart
helm install nullify-collector helm-charts/nullify-k8s-collector \
  -f values-production.yaml \
  --namespace nullify \
  --create-namespace
```

### **Verify Deployment**

```bash
# Check if the resources were created
kubectl get all -n nullify

# Check the CronJob
kubectl get cronjob -n nullify

# Check the ServiceAccount (should have IRSA annotation)
kubectl get serviceaccount nullify-k8s-collector-sa -n nullify -o yaml

# View the last job run
kubectl get jobs -n nullify

# Check logs from the latest job
kubectl logs -l job-name=<job-name> -n nullify
```

## 🏗️ **CloudFormation Deployment**

Deploy AWS infrastructure using CloudFormation templates for cross-account access and IAM role setup.

> ⚠️ **Important**: CloudFormation only sets up IAM roles and trust policies. For EKS integration, you must deploy Kubernetes resources separately using Helm charts.

```bash
# 1. Clone the repository
git clone https://github.com/Nullify-Platform/nullify-cloud-connector.git
cd nullify-cloud-connector/aws-integration-setup/cloudformation

# 2. Deploy the CloudFormation stack
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=your-company \
    ParameterKey=ExternalID,ParameterValue=your-external-id \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::ACCOUNT:role/ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=your-nullify-bucket \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=your-oidc-url \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2

# Note: ExternalID and CrossAccountRoleArn are provided in the Nullify configure page

# 3. Verify stack creation
aws cloudformation describe-stacks --stack-name nullify-aws-integration
```

**See:** [CloudFormation README](aws-integration-setup/cloudformation/README.md) for detailed instructions.

## 🔧 **Terraform Deployment**

Use Terraform's modular architecture for infrastructure-as-code deployments with version control and state management.

> ⚠️ **Important**: The AWS integration module only sets up IAM roles and trust policies. For full EKS integration, you must also deploy the Kubernetes resources using the separate `k8s-resources` module.

### **Multi-Cluster EKS Integration**

```bash
# 1. Clone the repository
git clone https://github.com/Nullify-Platform/nullify-cloud-connector.git
cd nullify-cloud-connector/aws-integration-setup/terraform/examples/multi-cluster-complete

# 2. Create terraform configuration
cp terraform.tfvars.example terraform.tfvars

# 3. Edit with your cluster ARNs and values (supports multiple regions)
cat > terraform.tfvars << EOF
customer_name = "your-company"
external_id   = "your-external-id"  # From Nullify configure page
nullify_role_arn = "arn:aws:iam::NULLIFY-ACCOUNT:role/ROLE"  # From Nullify configure page

# Multi-cluster support - clusters can be from different regions
eks_cluster_arns = [
  "arn:aws:eks:us-west-2:123456789012:cluster/prod-cluster",
  "arn:aws:eks:eu-west-1:123456789012:cluster/eu-cluster"
]

aws_region = "us-west-2"
s3_bucket_name = "your-nullify-bucket"  # From Nullify configure page
EOF

# 4. Initialize and apply
terraform init
terraform plan
terraform apply
```

### **AWS-Only Integration**

```bash
# For AWS resources only (no Kubernetes)
cd aws-integration-setup/terraform/examples/basic

cp ../../terraform.tfvars.example terraform.tfvars
# Edit with your values
terraform init && terraform apply
```

### **Module Architecture**

The Terraform configuration uses separate, focused modules:

- **`nullify-aws-integration`**: Creates IAM roles with multi-cluster OIDC trust policies
- **`k8s-resources`**: Deploys collector cronjob and RBAC to any cluster

**Benefits:**
- Deploy AWS resources once, K8s resources per cluster
- Multi-region support with automatic region detection
- Independent module lifecycle management

**See:** [Terraform README](aws-integration-setup/terraform/README.md) for detailed instructions.

## 📁 **Repository Structure**

```
nullify-cloud-connector/
├── 📋 README.md                          # This file - main documentation
├── 📄 LICENSE                            # MIT License
├── 🚫 .gitignore                         # Prevents sensitive file commits
├── 📖 IMPLEMENTATION.md                  # Technical implementation details
│
├── 🤖 .github/workflows/                 # CI/CD Automation
│   ├── helm-release.yml                  # Auto-publish Helm charts to GitHub Pages
│   ├── pr-validation.yml                 # PR validation and testing
│   └── auto-tag.yml                      # Auto-tag releases on version changes
│
├── ⚙️ helm-charts/                       # 🎯 KUBERNETES DEPLOYMENT
│   └── nullify-k8s-collector/            # Main Helm chart for K8s collector
│       ├── Chart.yaml                    # Chart metadata and version
│       ├── values.yaml                   # Default values (generic/safe)
│       ├── values-example.yaml           # Example production configuration
│       ├── README.md                     # Chart-specific documentation
│       └── templates/                    # Kubernetes resource templates
│           ├── namespace.yaml            # Namespace creation
│           ├── serviceaccount.yaml       # IRSA service account
│           ├── clusterrole.yaml          # Read-only cluster permissions
│           ├── clusterrolebinding.yaml   # RBAC binding
│           ├── cronjob.yaml              # Main collector CronJob
│           └── pre-install-job.yaml      # Pre-installation validation
│
└── aws-integration-setup/               # 🏗️ AWS INFRASTRUCTURE
    │
    ├── 🏗️ cloudformation/               # CloudFormation Templates
    │   ├── nullify-cloudformation-template.json  # Main CF template
    │   └── README.md                     # CloudFormation deployment guide
    │
    ├── 🔧 terraform/                     # Terraform Modules
    │   ├── modules/                      # Reusable Terraform modules
    │   │   ├── nullify-aws-integration/  # AWS IAM resources only
    │   │   │   ├── main.tf               # Core infrastructure resources
    │   │   │   ├── variables.tf          # Input variables
    │   │   │   ├── data.tf               # Data sources and policies
    │   │   │   ├── locals.tf             # Local values
    │   │   │   └── outputs.tf            # Output values
    │   │   └── k8s-resources/            # Kubernetes resources only
    │   │       ├── main.tf               # Kubernetes resources
    │   │       ├── variables.tf          # Input variables
    │   │       └── outputs.tf            # Output values
    │   ├── examples/                     # Example Terraform configurations
    │   │   ├── basic/                    # AWS-only integration
    │   │   └── multi-cluster-complete/   # Multi-cluster EKS integration
    │   ├── main.tf                       # Root module instantiation
    │   ├── variables.tf                  # Root input variables
    │   ├── outputs.tf                    # Root outputs
    │   ├── terraform.tfvars.example      # Example configuration
    │   └── README.md                     # Terraform documentation
    │
    ├── 📚 docs/                          # Additional Documentation
    │   ├── README.md                     # Documentation index
    │   ├── security-guidelines.md        # Security best practices
    │   └── troubleshooting.md            # Common issues and solutions
    │
    └── 🔧 scripts/                       # Utility Scripts
        ├── validate-deployment.sh        # Deployment validation
        ├── update-helm-repo.sh           # Update Helm repository
        ├── cleanup.sh                    # Clean removal script
        └── setup-aws-integration.sh      # AWS setup automation
```

### **Component Overview**

| Component | Purpose | Use When |
|-----------|---------|----------|
| **🎯 Helm Charts** | Deploy K8s collector (EKS via IRSA, GKE via Workload Identity) | You have EKS or GKE and prefer K8s-native tools |
| **🏗️ CloudFormation** | Set up AWS IAM roles and policies | You prefer AWS-native infrastructure |
| **🔧 Terraform** | Modular infrastructure-as-code with multi-cluster support | You use Terraform for infrastructure |
| **🤖 GitHub Actions** | Automated testing and publishing | You want CI/CD for chart updates |
| **📚 Documentation** | Setup guides and troubleshooting | You need detailed implementation help |

## 🔐 **Security Configuration**

### **IRSA (IAM Roles for Service Accounts)**

The collector uses IRSA for secure AWS authentication. You only need to provide the complete IAM role ARN:

```yaml
serviceAccount:
  annotations:
    # Complete IAM role ARN provided by Nullify configure page
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT-ID:role/ROLE-NAME"
```

### **Security Features**
- 🔒 **Non-root container** execution
- 🛡️ **Read-only root filesystem**
- 🚫 **No privilege escalation**
- 📊 **Minimal resource requests**
- 🎯 **Least-privilege RBAC**
- 🌍 **Multi-cluster security isolation**

## ⚙️ **Configuration Options**

### **Basic Configuration**

All required values are provided in the Nullify configure page.

```yaml
collector:
  aws:
    region: "us-west-2"              # Extract from your KMS key ARN
  clusterName: "your-cluster-name"   # Must match your actual EKS cluster name
  s3:
    bucket: "your-nullify-bucket"
    keyPrefix: "k8s-collector"
  kms:
    keyArn: "arn:aws:kms:us-west-2:123456789012:key/your-key-id"
  schedule: "0 2 * * *"              # Daily at 2 AM UTC

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/ROLE-NAME"
```

### **Multi-Cluster Configuration**

```hcl
# Terraform configuration for multiple clusters
eks_cluster_arns = [
  "arn:aws:eks:us-west-2:123456789012:cluster/prod-cluster",
  "arn:aws:eks:eu-west-1:123456789012:cluster/eu-cluster",
  "arn:aws:eks:us-west-2:123456789012:cluster/staging-cluster"
]

# Features:
# - Automatic region extraction from cluster ARNs
# - Dynamic OIDC provider discovery
# - Multi-region trust policy generation
# - Single IAM role trusts all specified clusters
```

### **Advanced Configuration**

```yaml
collector:
  # Data collection filters
  dataCollection:
    excludeNamespaces: "kube-system,kube-public"
    includeResources: "pods,services,deployments"
    metadataOnly: true  # Only collect metadata
  
  # Resource limits
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"
    requests:
      cpu: "200m"
      memory: "256Mi"
```

## 🔧 **Management Commands**

### **Repository Management**
```bash
# View available chart versions
helm search repo nullify/nullify-k8s-collector --versions

# Get chart information
helm show chart nullify/nullify-k8s-collector
helm show values nullify/nullify-k8s-collector
```

### **Deployment Management**
```bash
# Upgrade the chart
helm upgrade nullify-collector nullify/nullify-k8s-collector \
  -f values-production.yaml \
  --namespace nullify

# Uninstall the chart
helm uninstall nullify-collector --namespace nullify

# Trigger manual collection
kubectl create job --from=cronjob/nullify-k8s-collector manual-collection -n nullify
```

## 📚 **Documentation**

| Document | Description |
|----------|-------------|
| [📖 IMPLEMENTATION.md](IMPLEMENTATION.md) | Implementation details and technical overview |
| [📖 Chart README](helm-charts/nullify-k8s-collector/README.md) | Chart-specific documentation |
| [🏗️ CloudFormation README](aws-integration-setup/cloudformation/README.md) | CloudFormation template documentation |
| [🔧 Terraform README](aws-integration-setup/terraform/README.md) | Terraform modules documentation |
| [📚 Docs](aws-integration-setup/docs/README.md) | Additional documentation |

## 🐛 **Troubleshooting**

### **Common Issues**

**CronJob not running:**
```bash
kubectl describe cronjob nullify-k8s-collector -n nullify
kubectl get events -n nullify --sort-by='.lastTimestamp'
```

**IRSA authentication issues:**
```bash
kubectl logs -l app=nullify-k8s-collector -n nullify
```

**Permission errors:**
```bash
kubectl auth can-i --list --as=system:serviceaccount:nullify:nullify-k8s-collector-sa
```

**Multi-cluster configuration issues:**
```bash
# Check cluster ARN format
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.arn'

# Verify OIDC provider
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer'
```

### **Validation Script**
```bash
# Run deployment validation
./scripts/validate-deployment.sh
```

## 🤝 **Contributing**

1. **Fork** this repository
2. **Create** a feature branch
3. **Ensure** no sensitive data in commits
4. **Test** your changes with a real cluster
5. **Submit** a pull request

> 📝 **Note**: Never commit sensitive information like role ARNs, bucket names, or real configuration values.

## 📞 **Support**

- **Nullify Support**: Contact through official channels for configuration values
- **Chart Issues**: Use GitHub issues for template problems (no sensitive data)
- **Documentation**: Check existing docs before opening issues

## 📄 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🚨 **Security Reminder**

**Before deploying:**
1. 📖 Read [IMPLEMENTATION.md](IMPLEMENTATION.md) for technical details
2. 🔐 Obtain all required values from Nullify configure page (IAM role ARN, KMS key ARN, S3 bucket)
3. 🚫 Never commit `values-production.yaml`
4. ✅ Use `values-example.yaml` as a template only
5. 🔍 Verify IRSA configuration before deployment

**Remember**: This repository contains generic templates. Always use placeholder values and obtain real configuration from the Nullify configure page. 