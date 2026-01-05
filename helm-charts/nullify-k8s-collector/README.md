# Kubernetes Information Collector Helm Chart

This Helm chart deploys a Kubernetes collector for the Nullify platform to gather information about your cluster for security analysis.

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+

## Configuration

The following table lists the configurable parameters of the chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | If true, create a new service account | `true` |
| `serviceAccount.annotations` | Annotations for the service account (IAM role ARN from Nullify configure page) | `eks.amazonaws.com/role-arn: YOUR-NULLIFY-READ-ONLY-ROLE-ARN` |
| `serviceAccount.name` | Name of the service account | `nullify-k8s-collector-sa` |
| `collector.image.repository` | Image repository | `public.ecr.aws/w4o2j2x4/integrations` |
| `collector.image.tag` | Image tag | `k8s-collector-latest` |
| `collector.image.pullPolicy` | Pull policy | `Always` |
| `collector.schedule` | CronJob schedule | `0 0 * * *` (daily at midnight) |
| `collector.s3.bucket` | S3 bucket for storing data (from Nullify configure page) | `nullify-death-star-dast-k8s` |
| `collector.s3.keyPrefix` | S3 key prefix | `k8s-collector` |
| `collector.aws.region` | AWS region | `ap-southeast-2` |
| `collector.clusterName` | Cluster name identifier | `YOUR-CLUSTER-NAME` |
| `collector.kms.keyArn` | **REQUIRED**: KMS key ARN for encryption operations (from Nullify configure page) | `""` |
| `collector.debug.enabled` | Enable debug logging for troubleshooting | `false` |
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

### Other Kubernetes Clusters

For non-EKS clusters, you'll need to provide AWS credentials through other means:

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
