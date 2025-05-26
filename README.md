# 🛡️ Nullify Kubernetes Collector - Helm Chart

**Secure Helm chart for deploying Nullify's Kubernetes data collector in your EKS cluster.**

> 🚨 **SECURITY NOTICE**: This repository contains **GENERIC TEMPLATES ONLY**. See [SECURITY.md](SECURITY.md) for critical security guidelines.

## 🎯 **Overview**

This Helm chart deploys Nullify's k8s-collector as a CronJob in your Kubernetes cluster to securely collect cluster metadata for security scanning. The collector uses **IAM Roles for Service Accounts (IRSA)** for secure AWS authentication.

### **What's Included**
- ✅ **Production-ready Helm chart** with IRSA support
- ✅ **Security-focused configuration** (non-root, read-only filesystem)
- ✅ **CronJob deployment** for scheduled data collection
- ✅ **Comprehensive RBAC** permissions
- ✅ **Example configuration files** with placeholders
- ❌ **NO real account IDs, bucket names, or sensitive data**

## 🚀 **Quick Start**

### **Prerequisites**

1. **EKS Cluster** with IRSA enabled
2. **AWS Cross-account IAM Role** (created by Nullify)
3. **Helm 3.x** installed
4. **kubectl** configured for your cluster

**Contact Nullify Support** to obtain:
- Complete IAM role ARN for IRSA
- S3 bucket name for data storage
- Specific deployment instructions

### **Option 1: Install from Helm Repository (Recommended)**

```bash
# 1. Add the Nullify Helm repository
helm repo add nullify https://nullify-cloud-connector.github.io/aws-integration-setup/
helm repo update

# 2. Create your production values file
cat > values-production.yaml << EOF
collector:
  aws:
    region: "us-west-2"  # Your AWS region
  s3:
    bucket: "your-nullify-bucket-name"  # From Nullify support

serviceAccount:
  annotations:
    # Complete IAM role ARN from Nullify support
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/AWSIntegration-YourCompany-NullifyReadOnlyRole"
EOF

# 3. Install the chart
helm install nullify-collector nullify/k8s-collector \
  -f values-production.yaml \
  --namespace nullify \
  --create-namespace

# 4. Verify deployment
kubectl get all -n nullify
```

### **Option 2: Install from Source**

```bash
# 1. Clone this repository
git clone <repository-url>
cd aws-integration-setup

# 2. Create your production values file
cp charts/nullify-k8s-collector/values-example.yaml values-production.yaml

# 3. Edit with your actual values (provided by Nullify)
vi values-production.yaml

# 4. Install the chart
helm install nullify-collector charts/nullify-k8s-collector \
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

## 📁 **Repository Structure**

```
aws-integration-setup/
├── 📋 README.md                          # This file
├── 🔒 SECURITY.md                        # Security guidelines (READ FIRST!)
├── 📄 LICENSE                            # MIT License
├── 🚫 .gitignore                         # Prevents sensitive file commits
│
├── ⚙️ charts/nullify-k8s-collector/       # Main Helm chart
│   ├── Chart.yaml                        # Chart metadata
│   ├── values.yaml                       # Default values (generic)
│   ├── values-example.yaml               # Example production config
│   ├── README.md                         # Chart-specific documentation
│   └── templates/                        # Kubernetes manifests
│       ├── namespace.yaml                # Namespace creation
│       ├── serviceaccount.yaml           # IRSA service account
│       ├── clusterrole.yaml              # Read-only cluster permissions
│       ├── clusterrolebinding.yaml       # RBAC binding
│       ├── cronjob.yaml                  # Main collector job
│       └── pre-install-job.yaml          # Pre-installation tasks
│
├── 📚 docs/                              # Helm repository (GitHub Pages)
│   ├── README.md                         # Helm repository documentation
│   ├── index.yaml                        # Helm repository index
│   └── *.tgz                             # Packaged charts
│
├── 🔧 scripts/
│   ├── validate-deployment.sh            # Deployment validation
│   ├── update-helm-repo.sh               # Update Helm repository
│   └── cleanup.sh                        # Clean removal script
│
└── 🤖 .github/workflows/                 # GitHub Actions
    ├── helm-release.yml                  # Auto-publish to Helm repo
    ├── pr-validation.yml                 # PR validation and testing
    └── auto-tag.yml                      # Auto-tag releases
```

## 🔐 **Security Configuration**

### **IRSA (IAM Roles for Service Accounts)**

The collector uses IRSA for secure AWS authentication. You only need to provide the complete IAM role ARN:

```yaml
serviceAccount:
  annotations:
    # Complete IAM role ARN provided by Nullify support
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT-ID:role/ROLE-NAME"
```

### **Security Features**
- 🔒 **Non-root container** execution
- 🛡️ **Read-only root filesystem**
- 🚫 **No privilege escalation**
- 📊 **Minimal resource requests**
- 🎯 **Least-privilege RBAC**

## ⚙️ **Configuration Options**

### **Basic Configuration**

```yaml
collector:
  # AWS region
  aws:
    region: "us-west-2"
  
  # S3 storage (provided by Nullify)
  s3:
    bucket: "your-nullify-bucket"
    keyPrefix: "k8s-collector"
  
  # Collection schedule (cron format)
  schedule: "0 2 * * *"  # Daily at 2 AM UTC

# IRSA configuration (provided by Nullify)
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/ROLE-NAME"
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
helm search repo nullify/k8s-collector --versions

# Get chart information
helm show chart nullify/k8s-collector
helm show values nullify/k8s-collector
```

### **Deployment Management**
```bash
# Upgrade the chart
helm upgrade nullify-collector nullify/k8s-collector \
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
| [🔒 SECURITY.md](SECURITY.md) | **CRITICAL**: Security guidelines and best practices |
| [📖 docs/README.md](docs/README.md) | Helm repository documentation |
| [🔧 docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |
| [🏛️ docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Technical architecture overview |

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
1. 📖 Read [SECURITY.md](SECURITY.md) thoroughly
2. 🔐 Obtain **complete IAM role ARN** from Nullify support  
3. 🚫 Never commit `values-production.yaml`
4. ✅ Use `values-example.yaml` as a template only
5. 🔍 Verify IRSA configuration before deployment

**Remember**: This repository contains generic templates. Always use placeholder values and obtain real configuration from Nullify support. 