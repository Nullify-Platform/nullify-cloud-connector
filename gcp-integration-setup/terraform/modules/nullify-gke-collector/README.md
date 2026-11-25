# Nullify GKE Collector — Terraform Module

> **This module is optional.** Most customers do not need it. See the standard flow below.

## Standard flow (no Terraform needed)

The Nullify k8s-collector on GKE uses a projected Kubernetes ServiceAccount token signed by the cluster's own OIDC issuer. No GCP service account, no Workload Identity binding, no special cluster configuration required.

1. Get your cluster's OIDC issuer URL:

   ```bash
   gcloud container clusters describe CLUSTER --zone ZONE \
     --format='value(selfLink)'
   ```

2. Paste the URL into the Nullify console under **Settings → Connectors → GCP → GKE OIDC issuer URLs**.

3. Nullify returns the **role ARN**. Obtain the exact `collectorUploadPrefix`, bucket and KMS key from your deployment settings and confirm the paired backend rollout. Follow the maintained [GKE Helm installation example](../../../../helm-charts/nullify-k8s-collector/README.md#gke-with-a-projected-kubernetes-token) for values and installation commands. Copy the issued upload prefix exactly; do not construct it from the tenant ID.

**Prerequisites:** Any GKE cluster, K8s 1.22+. No GKE Workload Identity setup required.

Run the source-chart command from a reviewed repository checkout after release compatibility is confirmed. For the published chart 0.5.0, use that release's values and instructions rather than substituting the collector 4 image.

## Scope of this module

This module creates a GCP service account and a Workload Identity binding. The standard collector chart uses a projected Kubernetes service-account token to assume its AWS role and does not require these GCP identity resources.

Creating this module does not add a fallback authentication mode to that chart, configure AWS OIDC trust, or make a cluster without projected tokens supported. Use it only when Nullify confirms a separate deployment requirement for the GCP identity resources.

## What this module creates

| Resource | Purpose |
|---|---|
| `google_service_account` | OIDC identity anchor for the collector pod. No GCP IAM roles needed. |
| `google_service_account_iam_member` | Workload Identity binding (`roles/iam.workloadIdentityUser`). |

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
| `service_account_email` | GCP SA email |
| `service_account_unique_id` | 21-digit SA unique ID |


## Collector 4 source prefix cutover

See the [upgrade and rollback requirements](../../../../README.md#collector-4-source-prefix-cutover).
