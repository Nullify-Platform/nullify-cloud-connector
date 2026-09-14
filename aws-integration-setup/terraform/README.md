# Nullify AWS Integration Terraform

This Terraform configuration provides modular components for integrating with Nullify's security scanning platform, supporting both AWS-only and full EKS cluster integrations.

This directory targets AWS provider v5. If your project uses AWS provider v6, use `../terraform-v6/`.

## ⚠️ Important Notice

**EKS Integration**: The AWS integration module only sets up IAM roles and trust policies. Kubernetes access needs one of the two scan modes in [Kubernetes scan modes](#kubernetes-scan-modes).

## Requirements

- Terraform >= 1.5
- AWS provider `~> 5.33` in the root and examples. `modules/eks-managed-scan-access` needs `>= 5.33` (access entries arrived in 5.33.0); `modules/nullify-aws-integration` still accepts `~> 5.0`
- Kubernetes provider `~> 2.20` (only `modules/k8s-resources` and the `multi-cluster-complete` and `managed-scan` examples)

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
│   │   ├── outputs.tf              # Module outputs
│   │   └── tests/                  # terraform test suite (mocked providers)
│   ├── eks-managed-scan-access/    # EKS access entries for the managed scan (AWS provider only)
│   │   ├── versions.tf, variables.tf, main.tf, outputs.tf
│   │   └── tests/
│   └── k8s-resources/              # Kubernetes resources only
│       ├── providers.tf            # Kubernetes provider requirements
│       ├── variables.tf            # Module input variables
│       ├── main.tf                 # In-cluster collector
│       ├── managed_scan.tf         # List-only ClusterRole for the managed scan
│       ├── moved.tf                # Keeps pre-toggle collector state in place
│       ├── outputs.tf              # Module outputs
│       └── tests/
├── examples/
│   ├── basic/                      # AWS IAM only example
│   ├── managed-scan/               # One cluster, managed scan, no in-cluster agent
│   └── multi-cluster-complete/     # Two clusters, collector and/or managed scan
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
- **EKS Access Module**: Creates EKS access entries; needs no connection to the cluster API
- **K8s Module**: Deploys the collector CronJob and/or the managed-scan RBAC to any cluster
- **Independent Deployment**: Deploy AWS resources once, K8s resources per cluster
- **Multi-Region Support**: Region taken from each cluster ARN
- **Simplified Management**: Each module has focused responsibilities

## Examples

### **Basic Example** (`examples/basic/`)
- AWS IAM resources only
- No Kubernetes integration
- Minimal configuration for cloud-only scanning

### **Managed Scan** (`examples/managed-scan/`)
- One cluster, no in-cluster agent
- IAM role, access entry, and the list-only `nullify-readonly` ClusterRole

### **Multi-Cluster Complete** (`examples/multi-cluster-complete/`)
- AWS IAM + EKS integration for exactly two clusters
- `scan_mode`: `collector` (default), `managed` or `both`
- Clusters can be in different regions: each is read through an AWS provider in its own region

## Kubernetes scan modes

| | In-cluster collector | Managed scan |
|---|---|---|
| Runs in the cluster | CronJob with an IRSA service account | Nothing |
| Cluster endpoint | Any, including private-only | Public endpoint that admits Nullify's egress IPs |
| AWS setup | `enable_kubernetes_integration = true`, S3 bucket or access point | `eks-managed-scan-access`: one access entry per cluster |
| Kubernetes setup | `k8s-resources` (default) or the `nullify-k8s-collector` Helm chart | A list-only `nullify-readonly` ClusterRole and ClusterRoleBinding, applied by `k8s-resources` with `enable_collector = false, enable_managed_scan_rbac = true` |
| Upgrades | You update the image | None |

Both modes can run on the same role: IRSA uses `sts:AssumeRoleWithWebIdentity`, the managed scan uses `sts:AssumeRole` with the external ID.

## Managed EKS scan

Nullify lists Kubernetes resources from its own compute, using the read-only role this configuration creates. The scan only calls `list`, plus `get /version`.

### RBAC granted to Nullify (default, `authorization = "rbac"`)

The access entry carries the Kubernetes group `nullify-readonly`, bound to the ClusterRole `nullify-readonly`:

| API group | Resources (verb `list`) |
|---|---|
| core | nodes, namespaces, pods, services, persistentvolumeclaims, persistentvolumes, configmaps, secrets, resourcequotas, limitranges, serviceaccounts |
| apps | deployments, daemonsets, statefulsets, replicasets |
| networking.k8s.io | ingresses, networkpolicies |
| discovery.k8s.io | endpointslices |
| rbac.authorization.k8s.io | roles, rolebindings, clusterroles, clusterrolebindings |
| admissionregistration.k8s.io | validatingwebhookconfigurations, mutatingwebhookconfigurations, validatingadmissionpolicies, validatingadmissionpolicybindings |

Plus `get` on the non-resource URL `/version`. Kubernetes has no metadata-only permission for Secrets: `list secrets` permits reading values, whichever mode you pick.

### `authorization = "admin_view_policy"` (opt-in)

Associates `AmazonEKSAdminViewPolicy` at cluster scope, so no Kubernetes objects are needed. **It grants far more than the scan uses:** `get`, `list` and `watch` on every resource, including Secrets, custom resources and `pods/log`. On EKS 1.34 and earlier, `get pods/exec` is enough to exec into pods. Its grants do not show in `kubectl auth can-i --list`. The module prints a warning on every plan in this mode. `AmazonEKSViewPolicy` is not offered: it cannot list nodes, persistent volumes, Secrets, RBAC or admission objects.

### Prerequisites

- **The clusters must already exist when you plan.** `cluster_arns` drives `for_each` and each cluster is read with `data "aws_eks_cluster"`, so every ARN must be a literal or a value known at plan time. Calling this module in the same apply that creates the cluster fails with *"Invalid for_each argument ... depends on resource attributes that cannot be determined until apply"*. Create the cluster first (`terraform apply -target=module.eks`), then run a normal `terraform apply`; from then on the ARNs are in state and every later apply is a single step. The module is deliberately not restructured to defer the lookup: the preconditions below, and the endpoint `check`, only work against a cluster that can be read at plan.
- **Authentication mode.** Access entries need `API` or `API_AND_CONFIG_MAP`. Check with `aws eks describe-cluster --name <cluster> --query cluster.accessConfig.authenticationMode`. Switch (one-way) with `aws eks update-cluster-config --name <cluster> --access-config authenticationMode=API_AND_CONFIG_MAP`. The module fails at plan for `CONFIG_MAP` clusters.
- **Same account.** Nullify assumes the role in the cluster's own account, so deploy `nullify-aws-integration` in every account that owns a scanned cluster. The module rejects clusters in another account.
- **One region per module instance (AWS provider v5).** Instantiate `eks-managed-scan-access` once per region with `providers = { aws = aws.<region> }`, as `examples/multi-cluster-complete` does. `../terraform-v6/` handles every region in one instance.
- **Terraform identity.** `eks:DescribeCluster`, `eks:CreateAccessEntry`, `eks:DescribeAccessEntry`, `eks:UpdateAccessEntry`, `eks:DeleteAccessEntry` and `eks:TagResource`, plus `eks:AssociateAccessPolicy`, `eks:DisassociateAccessPolicy` and `eks:ListAssociatedAccessPolicies` for `admin_view_policy`. Creating the ClusterRole with `k8s-resources` needs rights to grant every permission in it, which in practice means cluster-admin. A GitOps controller (Flux, Argo CD) that already holds those rights can apply the same ClusterRole itself.
- **Pass `principal_unique_id`.** EKS ties an access entry to the role's ID, so a recreated role with the same ARN is silently not authorized. With `principal_unique_id = module.nullify_aws_integration.role_unique_id`, the entries are replaced with the role.
- **Existing access entry.** If this role is already mapped on a cluster, import it: `terraform import 'module.eks_managed_scan_access.aws_eks_access_entry.nullify["<cluster-arn>"]' <cluster-name>:<role-arn>`.

### Allowing Nullify to reach the EKS API endpoint

The managed scan connects to the cluster's public endpoint from Nullify's egress IPs for your Nullify region:

| Nullify region | Egress IPs |
|---|---|
| ap-southeast-2 | 13.55.32.104, 3.105.146.106, 13.211.99.100 |
| eu-central-1 | 18.198.60.231, 18.157.227.250, 18.185.152.197 |
| us-east-2 | 52.15.146.50, 16.58.40.80, 3.133.15.210 |

These modules never change `publicAccessCidrs`: the cluster belongs to your own IaC, and the API replaces the whole list. Instead:

- A `check` block warns on every plan when a cluster's public endpoint is disabled or misses a Nullify IP. It matches exact CIDRs, so a wider range that already covers the IPs still warns.
- The `endpoint_allowlist` output lists the missing CIDRs per cluster and an `aws eks update-cluster-config` command that keeps the existing CIDRs.
- If the cluster is in Terraform, add the CIDRs there:

```hcl
resource "aws_eks_cluster" "this" {
  vpc_config {
    endpoint_public_access = true
    public_access_cidrs    = concat(var.existing_public_access_cidrs, module.nullify_eks_access.nullify_egress_cidrs)
  }
}
```

Private-only clusters cannot use the managed scan; use the in-cluster collector.

### CONFIG_MAP clusters (aws-auth)

These modules do not manage `aws-auth`: writing it from Terraform replaces the whole `mapRoles` string and can drop node roles. If you cannot switch the authentication mode, add the role yourself and apply the RBAC with `k8s-resources`:

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::<account>:role/AWSIntegration-<customer>-NullifyReadOnlyRole
    username: nullify-managed-scan
    groups:
      - nullify-readonly
```

### Module usage

```hcl
module "nullify_eks_access" {
  source = "./modules/eks-managed-scan-access"

  principal_arn       = module.nullify_aws_integration.role_arn
  principal_unique_id = module.nullify_aws_integration.role_unique_id
  cluster_arns        = ["arn:aws:eks:us-west-2:123456789012:cluster/my-cluster"]
  nullify_region      = "us-east-2"
}

module "nullify_readonly_rbac" {
  source    = "./modules/k8s-resources"
  providers = { kubernetes = kubernetes.my_cluster }

  enable_collector         = false
  enable_managed_scan_rbac = true
}
```

Outputs: `access_entry_arns`, `authorization`, `kubernetes_group_name`, `nullify_egress_cidrs`, `clusters_for_nullify`, `endpoint_allowlist`.

The root configuration exposes the same module through `enable_managed_scan`, `managed_scan_cluster_arns`, `nullify_region`, `managed_scan_authorization` (default `rbac`) and `managed_scan_kubernetes_group`. The root has no Kubernetes provider, so in `rbac` mode apply the RBAC separately.

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

With several clusters in one apply, `data "aws_eks_cluster_auth"` tokens can expire (about 15 minutes) before the Kubernetes resources are created. Use the Kubernetes provider's `exec` block (`aws eks get-token`) for slow applies, or `../terraform-v6/`, whose examples use ephemeral tokens.

## Quick Start

### 1. AWS-Only Integration

```bash
cd examples/basic/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

### 2. Managed EKS Scan (no in-cluster agent)

```bash
cd examples/managed-scan/
cp terraform.tfvars.example terraform.tfvars
# Edit with your cluster ARN and Nullify region
terraform init && terraform apply
```

### 3. Multi-Cluster EKS Integration

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
- `enable_managed_scan`, `managed_scan_cluster_arns`, `nullify_region`, `managed_scan_authorization`, `managed_scan_kubernetes_group`: see [Managed EKS scan](#managed-eks-scan)

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

A key ARN is granted on its own. IAM does not resolve an alias in a policy's `Resource`, so an alias ARN also grants `arn:aws:kms:<region>:<account>:key/*` in the same Nullify account and region. Nullify's key policy is the real gate: the role can only use Nullify keys whose key policy allows it. The `kms_policy_resources` module output lists what was granted.

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
  cluster_name   = "cluster-a"
  s3_bucket_name = "my-scan-results-bucket" # or the S3 access point ARN from Nullify
  kms_key_arn    = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  aws_region     = "us-west-2"
  enable_debug   = false
}
```

`cluster_name` is required whenever `enable_collector` is true, and must differ per cluster. The collector uploads to `<prefix>/k8s-collector/<cluster_name>-data.json`, so two collectors sharing a name overwrite each other's inventory and Nullify only ever sees the one that ran last.

`k8s-resources` variables include `enable_collector` (default `true`), `enable_managed_scan_rbac` (default `false`), `collector_image`, `cronjob_schedule` (default `0 0 * * *`), `kubernetes_namespace`, `service_account_name` and `enable_debug`.

`collector_image` defaults to `public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.46.0`, a pinned tag of Nullify's ECR Public image. It is the same build as `k8s-collector-latest`, which the `nullify-k8s-collector` Helm chart deploys, so both install paths run the same collector. Earlier versions defaulted to `nullify/k8s-collector:latest` on Docker Hub, which Nullify does not publish; if you set that value explicitly, replace it.

## Outputs

### AWS Integration Module
- `role_arn`, `role_unique_id`: the created IAM role
- `deployment_summary`: Complete deployment information
- `cluster_integration_summary`: Multi-cluster setup details
- `all_oidc_ids`: List of OIDC provider IDs
- `kms_policy_resources`: Resources granted by the KMS policy

### K8s Resources Module
- `namespace_name`, `service_account_name`, `cluster_role_name`, `cluster_role_binding_name`, `cronjob_name`: collector resources (null when `enable_collector = false`)
- `managed_scan_cluster_role_name`, `managed_scan_cluster_role_binding_name`, `managed_scan_kubernetes_group`: managed-scan RBAC (null when disabled)

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
- The root and examples require AWS provider `>= 5.33`. Run `terraform init -upgrade` if your lock file pins an older 5.x.
- `k8s-resources` collector resources moved to `count` instances. `moved` blocks keep existing state, so a plan should show no changes; check it before applying.
- The root configuration no longer declares the Kubernetes provider. It never deployed Kubernetes resources.
- A cluster outside the AWS provider's region now fails at plan time with an explanation instead of a not-found error.
- The KMS policy grants `key/*` in the account and region of `kms_key_arn` when that value is an alias ARN. A key ARN grants only itself, as the CloudFormation template does.

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

# Module tests (mocked providers, Terraform >= 1.8; CI runs them at 1.8.5 and 1.10.5)
(cd modules/eks-managed-scan-access && terraform init -backend=false && terraform test)

# Plan deployment
terraform plan
```

## Support

- Example configurations: `./examples/*/`
- Contact Nullify support for integration assistance
