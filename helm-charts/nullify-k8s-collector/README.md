# Kubernetes Information Collector Helm Chart

This Helm chart deploys a Kubernetes collector for the Nullify platform to gather information about your cluster for security analysis.

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+

## Supported platforms

The same chart runs on **EKS** and **GKE**. Select the platform via `cloudProvider`:

| `cloudProvider` | Cluster  | How the collector authenticates to AWS              |
| --------------- | -------- | --------------------------------------------------- |
| `aws` (default) | EKS      | IRSA — ServiceAccount → AWS IAM role                |
| `gcp`           | GKE      | Workload Identity → `sts:AssumeRoleWithWebIdentity` |

In both cases the collector uploads cluster metadata to the same Nullify-managed
S3 bucket. No long-lived AWS credential is stored in the customer cluster.

## Configuration

The following table lists the configurable parameters of the chart and their default values.

> **Required values**: `collector.clusterName`, `collector.s3.bucket`, `collector.kms.keyArn`.
> Platform-specific required values are listed below. Get these from the Nullify configure page.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cloudProvider` | Platform the collector runs on: `aws` (EKS) or `gcp` (GKE) | `aws` |
| `serviceAccount.create` | If true, create a new service account | `true` |
| `serviceAccount.annotations` | Annotations for the service account. The chart renders only the annotation that matches `cloudProvider`. | See [values.yaml](./values.yaml) |
| `serviceAccount.name` | Name of the service account | `nullify-k8s-collector-sa` |
| `collector.image.repository` | Image repository | `public.ecr.aws/w4o2j2x4/integrations` |
| `collector.image.tag` | Image tag | `k8s-collector-latest` |
| `collector.image.pullPolicy` | Pull policy | `Always` |
| `collector.schedule` | CronJob schedule | `0 0 * * *` (daily at midnight) |
| `collector.s3.bucket` | S3 bucket for storing data (from Nullify configure page) | `YOUR-NULLIFY-S3-BUCKET` |
| `collector.s3.keyPrefix` | S3 key prefix | `k8s-collector` |
| `collector.aws.region` | AWS region | `us-east-1` |
| `collector.clusterName` | Cluster name (must match your actual cluster name) | `YOUR-CLUSTER-NAME` |
| `collector.kms.keyArn` | KMS key ARN for encryption (from Nullify configure page) | `""` |
| `collector.debug.enabled` | Enable debug logging for troubleshooting | `false` |
| `collector.gke.awsRoleArn` | **GKE only.** Nullify-owned federated AWS IAM role ARN (provided after cluster registration). | `""` |
| `collector.gke.audience` | **GKE only.** Token audience for the projected SA token. Do not change unless Nullify asks you to. | `sts.amazonaws.com` |
| `collector.gke.webIdentityTokenPath` | **GKE only.** In-pod path of the projected SA token. | `/var/run/secrets/tokens/gcp-sa-token` |
| `labels` | Additional labels for the collector resources | `null` |

## Security Context

The collector runs with:

- Non-root user (UID 1001)
- Read-only root filesystem
- No privilege escalation
- All capabilities dropped

## AWS IAM Configuration

> 📖 **Note**: The IAM role ARN required for IRSA configuration is provided in the Nullify configure page. Log in to your Nullify configure page, navigate to Configure > Integrations, and select AWS integration to obtain the required values.

### EKS with IRSA (IAM Roles for Service Accounts)

For EKS clusters, use IAM Roles for Service Accounts (IRSA):

1. Create an IAM policy with S3 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

2. Create an IAM role for the service account and attach the policy

3. In your values.yaml file, specify the IAM role ARN:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/NullifyCollectorRole"
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
  aws:
    region: "us-east-1"   # AWS region of the Nullify S3 bucket
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
helm install nullify-k8s-collector ./nullify-k8s-collector -f values-gke.yaml
```

### Other Kubernetes Clusters

For clusters outside EKS and GKE, you'll need to provide AWS credentials through
other means:

- Using AWS environment variables in the pod
- Using instance profiles for nodes running on EC2
- Using a solution like Kube2IAM or kiam

## Uninstallation

To uninstall/delete the `k8s-collector` deployment:

```bash
helm delete k8s-collector
```

## Troubleshooting

### Job Not Running

If the CronJob is not creating jobs on schedule:

1. Check that the cron schedule is valid:

   ```bash
   kubectl -n nullify get cronjob k8s-collector -o jsonpath='{.spec.schedule}'
   ```

2. Check the CronJob status:

   ```bash
   kubectl -n nullify describe cronjob k8s-collector
   ```

### Access Issues

If the job is failing due to S3 access issues:

1. Verify that the IAM role or credentials have the necessary permissions
2. Check that the S3 bucket exists and is accessible
3. Examine the job logs for detailed error messages

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
   helm upgrade nullify-collector nullify/nullify-k8s-collector -f values.yaml
   ```

3. **Check debug logs**:
   ```bash
   # Wait for the next job to run or trigger manually
   kubectl create job --from=cronjob/nullify-k8s-collector manual-debug-run -n nullify
   
   # View debug logs
   kubectl logs -l job-name=manual-debug-run -n nullify
   ```

Debug mode enables the `ENABLE_DEBUG_LOG` environment variable, which provides more detailed logging information to help diagnose collection issues.
