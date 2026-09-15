# Nullify AWS Integration Terraform (AWS Provider v6)

This directory mirrors `../terraform/` but targets **AWS Terraform provider v6** (`~> 6.0`). Use this if your project has already upgraded to AWS provider v6.

For AWS provider v5, use `../terraform/` instead. `../terraform/README.md` documents the modules, variables, outputs, the managed EKS scan and its prerequisites; this file covers what differs.

## What Differs from v5

- **Per-resource `region`.** AWS provider v6 accepts a `region` argument on most resources and data sources.
  - `nullify-aws-integration` reads each EKS cluster in the region from its ARN, so `eks_cluster_arns` can mix regions with one provider. There is no `eks_oidc_issuer_urls` variable here.
  - `eks-managed-scan-access` creates each access entry in its cluster's region, so one module instance covers every region. `managed_scan_cluster_arns` in the root can mix regions.
- **Ephemeral EKS token.** The `multi-cluster-complete` and `managed-scan` examples read the cluster token with `ephemeral "aws_eks_cluster_auth"`, which keeps it out of plan and state and needs Terraform >= 1.10:

```hcl
ephemeral "aws_eks_cluster_auth" "primary" {
  region = "eu-west-1"
  name   = "..."
}
token = ephemeral.aws_eks_cluster_auth.primary.token
```

## Requirements

- Terraform >= 1.8 (>= 1.10 for the `multi-cluster-complete` and `managed-scan` examples)
- AWS provider ~> 6.0
- Kubernetes provider ~> 2.20 (only `modules/k8s-resources` and the `multi-cluster-complete` and `managed-scan` examples)

## Architecture

```
terraform-v6/
├── modules/
│   ├── nullify-aws-integration/    # AWS IAM resources only
│   ├── eks-managed-scan-access/    # EKS access entries for the managed scan
│   └── k8s-resources/              # Collector and/or managed-scan RBAC
│   (each module has a tests/ terraform test suite)
├── examples/
│   ├── basic/                      # AWS IAM only example
│   ├── managed-scan/               # One cluster, managed scan, no in-cluster agent
│   └── multi-cluster-complete/     # Two clusters, collector and/or managed scan
├── versions.tf                     # AWS ~> 6.0
├── variables.tf
├── main.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars.example
└── README.md
```

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
# Edit with your cluster ARNs and values; set scan_mode for the managed scan
terraform init && terraform apply
```

## Managed EKS scan in one module instance

```hcl
module "nullify_eks_access" {
  source = "./modules/eks-managed-scan-access"

  principal_arn       = module.nullify_aws_integration.role_arn
  principal_unique_id = module.nullify_aws_integration.role_unique_id
  nullify_region      = "eu-central-1"
  cluster_arns = [
    "arn:aws:eks:eu-west-1:123456789012:cluster/prod",
    "arn:aws:eks:us-east-1:123456789012:cluster/us-prod",
  ]
}
```

The default `authorization = "rbac"` needs the list-only `nullify-readonly` ClusterRole on each cluster: apply it with `k8s-resources` (`enable_collector = false, enable_managed_scan_rbac = true`), or with any equivalent manifest of your own. `admin_view_policy` is a warned opt-in. The clusters must already exist when you plan; see `../terraform/README.md`.

## Required Variables

- `customer_name`: Your company/customer name (used in resource naming)
- `external_id`: External ID for cross-account access (provided by Nullify configure page)
- `nullify_role_arn`: Nullify's cross-account role ARN (provided by Nullify configure page)

## Optional Variables

- `aws_region`: AWS region for IAM resources (default: ap-southeast-2)
- `s3_bucket_name`: S3 bucket for scan results (optional)
- `nullify_s3_access_point_arn`: S3 access point for collector uploads (optional)
- `kms_key_arn`: KMS key ARN or alias ARN from the Nullify configure page; see "KMS" in `../terraform/README.md`. Optional for this module; required by `k8s-resources` whenever `enable_collector` is true
- `enable_kubernetes_integration`: Set to `true` for EKS integration
- `eks_cluster_arns`: List of EKS cluster ARNs to integrate with, in any region
- `enable_managed_scan`, `managed_scan_cluster_arns`, `nullify_region`, `managed_scan_authorization`, `managed_scan_kubernetes_group`: managed EKS scan
- `kubernetes_namespace`: Kubernetes namespace name (default: nullify)
- `service_account_name`: Collector service account name (default: nullify-k8s-collector-sa)
- `tags`: Resource tags
- `cronjob_schedule`: Deprecated and unused here; set the schedule on `k8s-resources`

`k8s-resources` requires `cluster_name` and `kms_key_arn` whenever `enable_collector` is true, with no unencrypted opt-out, and rejects `enable_collector` together with `enable_managed_scan_rbac`. `cluster_name` must match your actual cluster name exactly, must match a cluster registered on the Nullify configure page, and must differ per cluster: the collector uploads to `<prefix>/k8s-collector/<cluster_name>-data.json`, and Nullify joins that upload on the name. See "Kubernetes Resources" and "KMS" in `../terraform/README.md`.

`k8s-resources` defaults `collector_image` to `public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.46.0`, the same build as the `k8s-collector-latest` tag the Helm chart deploys. Replace any explicit `nullify/k8s-collector:latest`: Nullify does not publish that Docker Hub image.

## Upgrade Notes

- `k8s-resources` now requires `cluster_name` while `enable_collector` is true, and sets it as the collector's `CLUSTER_NAME`. A deployment that never set it was uploading to `k8s-collector/default-name-data.json`; after this change it uploads to `k8s-collector/<cluster_name>-data.json`. The old object is in Nullify's bucket, which your role cannot read or delete: ask Nullify to remove the stale `default-name` cluster, and register the new name on the configure page before the next run.
- `k8s-resources` now requires `kms_key_arn` while `enable_collector` is true, with no opt-out. The shipped collector images refuse to upload without KMS encryption, so a deployment that left it empty was collecting successfully and then failing every upload. Set the value from the configure page; ask Nullify for a key if you have none.
- `k8s-resources` collector resources moved to `count` instances. `moved` blocks keep existing state, so a plan should show no changes; check it before applying.
- The KMS policy grants `key/*` in the account and region of `kms_key_arn` whenever that account is not your own, for alias ARNs and key ARNs alike. An ARN in your own account grants only that key.

## Validation

```bash
terraform fmt -recursive
terraform validate
terraform plan
```
