# Kubernetes Information Collector Helm Chart

This Helm chart deploys a Kubernetes collector for the Nullify platform to gather information about your cluster for security analysis.

## Prerequisites

- Kubernetes 1.21+ (the chart uses `batch/v1` CronJob)
- Helm 3
- **EKS:** the Nullify AWS integration deployed with its EKS integration enabled (see [AWS IAM Configuration](#aws-iam-configuration))
- **GKE:** the cluster registered with Nullify (see [GKE](#gke-with-workload-identity-federation))
- Egress from the collector pod over HTTPS to `public.ecr.aws`, and to STS and S3 in the Nullify bucket's region

> **Image tag:** the default `collector.image.tag` is the floating `k8s-collector-latest`, pulled on every run.
> Pin a versioned tag once Nullify publishes one.

## Supported platforms

The same chart runs on **EKS** and **GKE**. Select the platform via `cloudProvider`:

| `cloudProvider` | Cluster  | How the collector authenticates to AWS              |
| --------------- | -------- | --------------------------------------------------- |
| `aws` (default) | EKS      | IRSA — ServiceAccount → AWS IAM role                |
| `gcp`           | GKE      | Workload Identity → `sts:AssumeRoleWithWebIdentity` |

In both cases the collector uploads cluster metadata to the same Nullify-managed
S3 bucket. No long-lived AWS credential is stored in the customer cluster.

## Installation

The chart does not create its namespace. Let Helm create it:

```bash
helm repo add nullify https://nullify-platform.github.io/nullify-cloud-connector/
helm repo update
helm upgrade --install nullify-k8s-collector nullify/nullify-k8s-collector \
  --namespace nullify --create-namespace \
  -f values-production.yaml
```

With Flux, set `spec.targetNamespace: nullify` and `spec.install.createNamespace: true` on the HelmRelease.

All namespaced objects go to `serviceAccount.namespace` (default `nullify`), whatever `--namespace` says; set it to `""` to use the release namespace.
On EKS keep the defaults: the connector's IRSA trust only allows `system:serviceaccount:nullify:nullify-k8s-collector-sa`.

The chart refuses to render when a required value is missing or still a placeholder, and names the value in the error.

## Configuration

> **Required values**: `collector.clusterName`, `collector.s3.bucket`, `collector.kms.keyArn`, and
> `serviceAccount.annotations."eks.amazonaws.com/role-arn"` (EKS) or `collector.gke.awsRoleArn` (GKE).
> Get these from the Nullify configure page.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cloudProvider` | Platform the collector runs on: `aws` (EKS) or `gcp` (GKE) | `aws` |
| `serviceAccount.create` | If true, create a new service account | `true` |
| `serviceAccount.requireRoleArn` | EKS: fail the render unless `eks.amazonaws.com/role-arn` is an `arn:aws:iam::` role ARN. Set `false` when the pod gets AWS credentials another way (see [Other Kubernetes Clusters](#other-kubernetes-clusters)). | `true` |
| `serviceAccount.annotations` | Annotations for the service account. The chart renders only the annotation that matches `cloudProvider`. | `eks.amazonaws.com/role-arn: ""` |
| `serviceAccount.name` | Name of the service account | `nullify-k8s-collector-sa` |
| `serviceAccount.namespace` | Namespace of every namespaced object; `""` means the release namespace. Must already exist. | `nullify` |
| `collector.image.repository` | Image repository | `public.ecr.aws/w4o2j2x4/integrations` |
| `collector.image.tag` | Image tag | `k8s-collector-latest` |
| `collector.image.pullPolicy` | Pull policy | `Always` |
| `collector.schedule` | CronJob schedule | `0 0 * * *` (daily at midnight) |
| `collector.s3.bucket` | S3 bucket for storing data (from Nullify configure page) | `""` (required) |
| `collector.s3.keyPrefix` | S3 key prefix | `k8s-collector` |
| `collector.aws.region` | Region of the **Nullify S3 bucket**, not your cluster. Defaults to the region in `collector.kms.keyArn`; any other value is rejected, because S3 only accepts a KMS key from the bucket's region. | `""` |
| `collector.clusterName` | Cluster name (must match your actual cluster name) | `""` (required) |
| `collector.kms.keyArn` | KMS key ARN `arn:aws:kms:<region>:<account-id>:key/<key-id>` or alias ARN `arn:aws:kms:<region>:<account-id>:alias/<name>`, from the Nullify configure page. With an alias, the IAM role's KMS statement must cover the key the alias resolves to, for example `arn:aws:kms:<region>:<account-id>:key/*`; see [KMS alias ARNs](#kms-alias-arns). | `""` (required) |
| `collector.debug.enabled` | Enable debug logging for troubleshooting | `false` |
| `collector.gke.awsRoleArn` | **GKE only.** Nullify-owned federated AWS IAM role ARN (provided after cluster registration). | `""` |
| `collector.gke.audience` | **GKE only.** Token audience for the projected SA token. Do not change unless Nullify asks you to. | `sts.amazonaws.com` |
| `collector.gke.webIdentityTokenPath` | **GKE only.** In-pod path of the projected SA token. | `/var/run/secrets/tokens/gcp-sa-token` |
| `nodeSelector` / `tolerations` | Collector pod placement | `{}` / `[]` |
| `labels` | Additional labels for the collector resources | `{}` |

The collector has no namespace or resource filters: it always lists every kind its ClusterRole allows, in every namespace.

## Security Context

The collector container runs with:

- `runAsNonRoot: true`
- Read-only root filesystem
- No privilege escalation
- All capabilities dropped

## AWS IAM Configuration

> 📖 **Note**: The IAM role ARN, S3 bucket and KMS key ARN are provided in the Nullify configure page (Configure > Integrations > AWS).

### EKS with IRSA (IAM Roles for Service Accounts)

Do not create the IRSA role by hand. The Nullify AWS integration role gains the collector's trust and permissions when you enable its EKS integration:

- **CloudFormation** ([template](../../aws-integration-setup/cloudformation/README.md)): update the stack with `EnableEKSIntegration=true`, `EKSOidcProviderURL=oidc.eks.<cluster-region>.amazonaws.com/id/<ISSUER_ID>` (no `https://`), `NullifyS3Bucket` and `NullifyKMSKeyArn` (the key ARN).
- **Terraform** ([module](../../aws-integration-setup/terraform/README.md)): set `enable_kubernetes_integration = true`, `eks_cluster_arns`, `s3_bucket_name` and `kms_key_arn`. `kubernetes_namespace` and `service_account_name` must match this chart's `serviceAccount.namespace` and `serviceAccount.name`. Deploy the collector with either this chart or the `k8s-resources` module, not both.

The cluster needs an IAM OIDC provider (`eksctl utils associate-iam-oidc-provider --cluster <name> --approve`).

The collector only uploads. It needs `s3:PutObject` on the Nullify bucket and `kms:GenerateDataKey` on the key, both granted by the integration. It never reads from the bucket, and the integration explicitly denies `s3:GetObject`.

### KMS alias ARNs

IAM evaluates KMS permissions against the key an alias resolves to, not the alias. When `collector.kms.keyArn` is an alias ARN, the IAM role's KMS statement must cover that key, for example `kms:GenerateDataKey` on `arn:aws:kms:<region>:<account-id>:key/*` in Nullify's KMS account and region. Otherwise uploads are denied.

- **CloudFormation:** connector releases that include PR #64 grant `key/*` in the account and region of the `NullifyKMSKeyArn` parameter. A stack created from an earlier template grants only the ARN it was given; update it to a later release.
- **Terraform:** the module accepts an alias in `kms_key_arn`. Check that your module version's KMS statement also covers `key/*`; one that grants only `kms_key_arn` denies uploads.
- Either way, a key ARN (`key/<key-id>`) works with every version.

Then set the role ARN in your values:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/AWSIntegration-yourcompany-NullifyReadOnlyRole"
```

### GKE with Workload Identity Federation

For GKE clusters, the collector authenticates to AWS without any long-lived credential.
The flow is:

1. GKE projects a Google-signed ServiceAccount token into the collector pod.
2. The collector forwards that token to AWS STS `AssumeRoleWithWebIdentity`.
3. AWS validates the token against the Google OIDC provider and returns short-lived
   credentials for a Nullify-owned IAM role scoped to your S3 prefix.

#### One-time onboarding

1. **Get your cluster's OIDC issuer URL** and share it with Nullify:

   ```bash
   gcloud container clusters describe YOUR-CLUSTER --zone YOUR-ZONE \
     --format='value(selfLink)'
   ```

   This outputs something like:
   `https://container.googleapis.com/v1/projects/my-project/locations/us-central1-a/clusters/prod`

2. **Share the OIDC issuer URL with Nullify** (via the configure page or support).
   Nullify registers it and gives you back the **role ARN** to use in the Helm values.

No GCP service accounts, Workload Identity bindings, or special cluster configuration required.
The chart uses a projected Kubernetes ServiceAccount token signed by the cluster's OIDC issuer.

#### Helm values

```yaml
cloudProvider: gcp

collector:
  clusterName: "my-gke-cluster"
  s3:
    bucket: "your-nullify-bucket"
  kms:
    keyArn: "arn:aws:kms:us-east-1:123456789012:key/your-key-id"
  gke:
    # Provided by Nullify after you register the cluster.
    awsRoleArn: "arn:aws:iam::123456789012:role/NullifyK8sCollectorRole"
```

Then install:

```bash
helm upgrade --install nullify-k8s-collector nullify/nullify-k8s-collector \
  --namespace nullify --create-namespace -f values-gke.yaml
```

### Other Kubernetes Clusters

For clusters outside EKS and GKE, or EKS without IRSA, you'll need to provide AWS
credentials through other means, and set `serviceAccount.requireRoleArn: false`
so the chart renders without the role-arn annotation:

- Using EKS Pod Identity for the collector's ServiceAccount
- Using AWS environment variables in the pod
- Using instance profiles for nodes running on EC2
- Using a solution like Kube2IAM or kiam

## Upgrading to 0.4.0

- `namespace.create` and `namespace.requireNamespace` are removed, along with the pre-install namespace hook and the `bitnami/kubectl` Job. Existing namespaces are not deleted. New installs need `--create-namespace`, or an existing namespace.
- `collector.dataCollection.*` is removed. The collector never read `EXCLUDE_NAMESPACES`, `INCLUDE_RESOURCES` or `METADATA_ONLY`.
- `collector.clusterName`, `collector.s3.bucket` and `collector.kms.keyArn` now default to `""`, and rendering fails when they are empty or still the old placeholders. The EKS role-arn annotation is validated the same way, unless `serviceAccount.requireRoleArn: false`.
- `collector.kms.keyArn` must be an `arn:aws:kms:` key or alias ARN. With an alias, the IAM role's KMS statement must cover the resolved key (for example `arn:aws:kms:<region>:<account-id>:key/*`), or uploads are denied; see [KMS alias ARNs](#kms-alias-arns).
- `collector.aws.region` now defaults to the KMS key's region instead of `us-east-1`.
- `helm upgrade --reuse-values` from 0.2.0 keeps 0.2.0's defaults, including `collector.aws.region: us-east-1`, so the region check fails unless the key is in `us-east-1`. Upgrade with `--reset-then-reuse-values` (Helm 3.14+) or `-f <your values>`, or set `collector.aws.region` to the key's region.
- `nodeSelector` and `tolerations` now apply to the collector pod; before, only the removed pre-install Job used them.

## Uninstallation

```bash
helm uninstall nullify-k8s-collector --namespace nullify
kubectl delete namespace nullify   # optional; Helm does not delete the namespace
```

## Troubleshooting

### Job Not Running

If the CronJob is not creating jobs on schedule:

1. Check that the cron schedule is valid:

   ```bash
   kubectl -n nullify get cronjob nullify-k8s-collector -o jsonpath='{.spec.schedule}'
   ```

2. Check the CronJob status:

   ```bash
   kubectl -n nullify describe cronjob nullify-k8s-collector
   ```

### Access Issues

If the job is failing due to S3 access issues:

1. `AccessDenied` on `kms:GenerateDataKey` with an alias in `collector.kms.keyArn`: the IAM role's KMS statement does not cover the key the alias resolves to. Grant `arn:aws:kms:<region>:<account-id>:key/*` in Nullify's KMS account (see [KMS alias ARNs](#kms-alias-arns)), or use the key ARN.
2. `AccessDenied` on `sts:AssumeRoleWithWebIdentity`: the service account must be `nullify/nullify-k8s-collector-sa`, and the integration's EKS OIDC provider URL must match the cluster.
3. Wrong-region or redirect errors: `collector.aws.region` must be the Nullify bucket's region (leave it empty).
4. Examine the job logs for detailed error messages.

### Debug Mode

To enable debug logging for troubleshooting:

1. **Enable debug mode** in your values file:
   ```yaml
   collector:
     debug:
       enabled: true
   ```

2. **Upgrade the deployment**:
   ```bash
   helm upgrade nullify-k8s-collector nullify/nullify-k8s-collector -n nullify -f values.yaml
   ```

3. **Check debug logs**:
   ```bash
   # Wait for the next job to run or trigger manually
   kubectl create job --from=cronjob/nullify-k8s-collector manual-debug-run -n nullify
   
   # View debug logs
   kubectl logs -l job-name=manual-debug-run -n nullify
   ```

Debug mode enables the `ENABLE_DEBUG_LOG` environment variable, which provides more detailed logging information to help diagnose collection issues.
