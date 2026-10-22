# Nullify GKE Collector — Terraform Module

> **This module is optional.** Most customers do not need it. See the standard flow below.

## Standard flow (no Terraform needed)

The Nullify k8s-collector on GKE uses a projected Kubernetes ServiceAccount token signed by the cluster's own OIDC issuer. No GCP service account, no Workload Identity binding, no special cluster configuration required.

1. Get your cluster's OIDC issuer URL:

   ```bash
   gcloud container clusters describe CLUSTER --zone ZONE \
     --format='value(selfLink)'
   ```

2. Paste the URL into the Nullify console under **Settings → Cloud Integrations → GCP → GKE Clusters**.

3. Nullify returns the **role ARN**. Deploy the Helm chart:

   ```yaml
   cloudProvider: gcp

   collector:
     clusterName: "my-gke-cluster"
     aws:
       region: "us-east-1"
     s3:
       bucket: "your-nullify-bucket"
     gke:
       awsRoleArn: "arn:aws:iam::123456789012:role/..."  # from Nullify
   ```

   ```bash
   helm install nullify-collector nullify/nullify-k8s-collector -f values-gke.yaml
   ```

**Prerequisites:** Any GKE cluster, K8s 1.22+. No GKE Workload Identity setup required.

## When to use this module

This module creates a GCP service account with a Workload Identity binding. It is only needed if:

- Your cluster does not support projected service account tokens (K8s < 1.22, extremely rare on GKE)
- You need the GCP metadata endpoint auth path instead of the projected token path

For all other cases, use the standard flow above.

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

Collector image `k8s-collector-4.0.0` requires the source-qualified upload prefix
returned by Nullify settings as `collectorUploadPrefix`. Upgrade the image and
prefix together. The old shared prefix is rejected; existing shared-prefix
objects are never imported as a fallback.

- Helm: copy the value into `collector.s3.keyPrefix`.
- Terraform: pass `collector_upload_prefix` to both the AWS integration role
  module and each `k8s-resources` collector module.
- CloudFormation: set `CollectorUploadPrefix` to the exact value, including its
  trailing slash. An enabled EKS collector without this value fails validation.

The paired Nullify backend release scopes bucket, access point and federated
OIDC role permissions to each source, and resolves ingestion by source plus
cluster name. Publish collector 4 and deploy that backend before rolling out
these templates. Require a fresh source-bound snapshot after each upgrade.
