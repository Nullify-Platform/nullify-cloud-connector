# Nullify GKE Collector — Terraform Module

Creates the GCP-side resources needed to deploy the [Nullify Kubernetes collector](../../../helm-charts/nullify-k8s-collector/) on a GKE cluster.

## What this module creates

| Resource | Purpose |
|---|---|
| `google_service_account` | OIDC identity anchor — the collector pod impersonates this SA via Workload Identity. **No GCP IAM roles are needed**; the SA only signs tokens that AWS STS validates. |
| `google_service_account_iam_member` | Workload Identity binding (`roles/iam.workloadIdentityUser`) that lets the in-cluster Kubernetes ServiceAccount impersonate the GCP SA. |

## Prerequisites

- **GKE Workload Identity** must be enabled on the cluster (`--workload-pool=PROJECT.svc.id.goog`). This module does not enable it — it's a cluster-level setting.
- **Terraform** >= 1.3 with the `google` provider >= 4.0.

## Usage

```hcl
module "nullify_gke_collector" {
  source     = "./modules/nullify-gke-collector"
  project_id = "my-gcp-project"
}
```

After `terraform apply`:

1. Share the `service_account_unique_id` output with Nullify. Nullify adds it to the federated IAM role's trust-policy allowlist and returns the AWS role ARN.
2. Deploy the Helm chart:

```yaml
# values-gke.yaml
cloudProvider: gcp

collector:
  clusterName: "my-gke-cluster"
  aws:
    region: "us-east-1"           # Region of the Nullify S3 bucket
  s3:
    bucket: "your-nullify-bucket" # Provided by Nullify
  kms:
    keyArn: "arn:aws:kms:..."     # Provided by Nullify
  gke:
    nullifyAwsRoleArn: "arn:aws:iam::123456789012:role/..." # Provided by Nullify

serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: "<service_account_email output>"
```

```bash
helm install nullify-k8s-collector ./nullify-k8s-collector -f values-gke.yaml
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project_id` | GCP project where the GKE cluster runs | `string` | — | yes |
| `service_account_name` | Name of the GCP SA to create | `string` | `nullify-k8s-collector` | no |
| `k8s_namespace` | Kubernetes namespace (must match Helm `serviceAccount.namespace`) | `string` | `nullify` | no |
| `k8s_service_account_name` | Kubernetes SA name (must match Helm `serviceAccount.name`) | `string` | `nullify-k8s-collector-sa` | no |

## Outputs

| Name | Description |
|---|---|
| `service_account_email` | GCP SA email — use as the `iam.gke.io/gcp-service-account` annotation in Helm values |
| `service_account_unique_id` | 21-digit SA unique ID — share with Nullify for the AWS trust-policy allowlist |
