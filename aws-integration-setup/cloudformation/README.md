# Nullify AWS Integration - CloudFormation Template

This directory contains a CloudFormation template for setting up AWS IAM roles and permissions required for Nullify's AWS integration.

## ⚠️ Important Notice

**EKS Integration**: The EKS integration created by this CloudFormation template only sets up the necessary IAM roles and trust policies. For the integration to be fully functional, you must deploy the Kubernetes cronjob resources separately using Helm charts or other Kubernetes deployment methods. The CloudFormation template alone does not deploy any Kubernetes resources. To scan EKS without running anything in the cluster, see [Managed EKS scan](#managed-eks-scan-no-in-cluster-agent).

## Overview

This template creates:
- IAM Role with cross-account trust to Nullify's AWS account
- Multiple IAM managed policies (split due to size limits)
- Support for both direct role assumption and EKS OIDC integration
- Comprehensive AWS service read permissions with security controls

## Prerequisites

1. **Obtain Configuration Values from Nullify Configure Page**:
   - Log in to your Nullify configure page
   - Navigate to Configure > Integrations
   - Select AWS integration to begin setup
   - Note the provided values:
     - External ID for your account
     - Nullify's cross-account role ARN
     - S3 bucket name (for Kubernetes integration)
     - KMS ARN (optional, for key management operations): an alias ARN or a key ARN; both are accepted

2. **AWS Requirements**:
   - AWS CLI configured with appropriate permissions
   - IAM permissions to create roles and policies

3. **For EKS Integration** (optional):
   - EKS cluster with OIDC provider enabled
   - OIDC provider URL (see [Getting EKS OIDC URL](#getting-eks-oidc-url) below)
   - **Helm charts or Kubernetes manifests** to deploy the collector cronjobs

> 📖 **Reference**: For detailed setup instructions, see the [Nullify AWS Integration Documentation](https://docs.nullify.ai/integrations/aws/configuration).

**Alternative**: Contact Nullify Support for assistance with configuration values.

## Getting EKS OIDC URL

If you're enabling EKS integration, you'll need the OIDC provider URL from your EKS cluster.

### Method 1: AWS CLI (Recommended)
```bash
# Get OIDC URL for your cluster
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text

# Remove the https:// prefix for the CloudFormation parameter
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||'
```

**Example output:**
```
https://oidc.eks.us-west-2.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890
```

**For CloudFormation parameter (without https://):**
```
oidc.eks.us-west-2.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890
```

### Method 2: AWS Console
1. Go to **Amazon EKS** in the AWS Console
2. Click on your cluster name
3. Go to the **Configuration** tab
4. Under **Details**, look for **OpenID Connect provider URL**

### Method 3: kubectl (if you have cluster access)
```bash
kubectl get configmap aws-auth -n kube-system -o yaml | grep "oidc"
```

### OIDC URL Format
- **Full URL format**: `https://oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID`
- **For CloudFormation parameter**: Use only the part **after** `https://`
- **Example**: If full URL is `https://oidc.eks.us-west-2.amazonaws.com/id/ABC123`, use `oidc.eks.us-west-2.amazonaws.com/id/ABC123`

### Enabling OIDC on EKS (if not already enabled)
```bash
# Check if OIDC is enabled
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc'

# If null, enable OIDC provider
eksctl utils associate-iam-oidc-provider --cluster YOUR_CLUSTER_NAME --approve
```

## Quick Start

### 1. Deploy via AWS Console

1. Download `nullify-cloudformation-template.json`
2. Go to CloudFormation console
3. Create new stack
4. Upload template file
5. Fill in parameters with values from Nullify configure page
6. Deploy stack

### 2. Deploy via AWS CLI

```bash
# Deploy the stack
# Note: ExternalID, CrossAccountRoleArn, and NullifyS3Bucket values are provided in the Nullify configure page
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
  --capabilities CAPABILITY_NAMED_IAM

# Check deployment status
aws cloudformation describe-stacks \
  --stack-name nullify-aws-integration \
  --query 'Stacks[0].StackStatus'

# Get the role ARN
aws cloudformation describe-stacks \
  --stack-name nullify-aws-integration \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

### 3. Deploy with EKS Integration

```bash
# For EKS clusters, enable integration
# First, get your OIDC URL (see "Getting EKS OIDC URL" section above)
# Note: ExternalID, CrossAccountRoleArn, and NullifyS3Bucket values are provided in the Nullify configure page
OIDC_URL=$(aws eks describe-cluster --name YOUR_CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')

aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=$OIDC_URL \
  --capabilities CAPABILITY_NAMED_IAM

# Or manually with a specific OIDC URL:
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=EnableEKSIntegration,ParameterValue=true \
    ParameterKey=EKSOidcProviderURL,ParameterValue=A78D8794A06CAE5791C5812CDB164C7D.gr7.ap-southeast-2.eks.amazonaws.com \
  --capabilities CAPABILITY_NAMED_IAM
```

### 4. Deploy with KMS Integration (Optional)

Pass the KMS ARN shown on the Nullify configure page as `NullifyKMSKeyArn`. Both forms are accepted:

- an alias ARN, `arn:aws:kms:<region>:<account>:alias/<name>`, which the configure page shows today;
- a key ARN, `arn:aws:kms:<region>:<account>:key/<key-id>`, including multi-Region `key/mrk-...` keys. The configure page will show the key ARN once Nullify rolls that change out.

```bash
# Deploy with the KMS ARN for key management operations
aws cloudformation create-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=CustomerName,ParameterValue=yourcompany \
    ParameterKey=ExternalID,ParameterValue=YOUR-EXTERNAL-ID \
    ParameterKey=CrossAccountRoleArn,ParameterValue=arn:aws:iam::NULLIFY-ACCOUNT:role/NULLIFY-ROLE \
    ParameterKey=NullifyS3Bucket,ParameterValue=NULLIFY-BUCKET \
    ParameterKey=NullifyKMSKeyArn,ParameterValue=arn:aws:kms:us-west-2:123456789012:alias/NULLIFY-ALIAS \
  --capabilities CAPABILITY_NAMED_IAM
```

IAM ignores alias ARNs for key operations, so the KMS policy grants its actions on the ARN you pass and on `arn:aws:kms:<region>:<account>:key/*` in the same Nullify account and region. Nullify's key policy is the real gate: the role can only use Nullify keys whose key policy allows it. Either form produces a working grant, so an existing stack does not need updating when the configure page changes. The `KMSPolicyResource` stack output lists both resources.

Update an existing stack, keeping its current values:

```bash
aws cloudformation update-stack \
  --stack-name nullify-aws-integration \
  --template-body file://nullify-cloudformation-template.json \
  --parameters \
    ParameterKey=AWSRegion,UsePreviousValue=true \
    ParameterKey=CrossAccountRoleArn,UsePreviousValue=true \
    ParameterKey=CustomerName,UsePreviousValue=true \
    ParameterKey=EKSOidcProviderURL,UsePreviousValue=true \
    ParameterKey=EnableEKSIntegration,UsePreviousValue=true \
    ParameterKey=ExternalID,UsePreviousValue=true \
    ParameterKey=NullifyS3Bucket,UsePreviousValue=true \
    ParameterKey=NullifyKMSKeyArn,UsePreviousValue=true \
  --capabilities CAPABILITY_NAMED_IAM
```

`UsePreviousValue=true` only works for parameters the stack's current template already has. A stack deployed from an older template version may lack `EKSOidcProviderURL`, `EnableEKSIntegration` or `NullifyKMSKeyArn`: for those, replace `UsePreviousValue=true` with `ParameterValue=...` (or drop the line to take the default), and keep `--template-body file://nullify-cloudformation-template.json` so the new template is used.

### 5. Collector upload target

The Nullify configure page shows the upload target for the Helm chart's `collector.s3.bucket`. Which form it shows decides the setup:

- **An S3 access point ARN** (`arn:aws:s3:REGION:NULLIFY-ACCOUNT:accesspoint/NAME`): first set `NullifyS3AccessPointArn` to that ARN in this stack, then use the same ARN as `collector.s3.bucket`. Without the parameter, uploads fail with `AccessDenied`: a grant on the bucket does not cover requests made through an access point.
- **A bucket name**: use it as `collector.s3.bucket` and leave `NullifyS3AccessPointArn` empty. That bucket is `NullifyS3Bucket`.

With `EnableEKSIntegration=true` and `NullifyS3AccessPointArn` set, the S3 access policy also allows `s3:PutObject`, `s3:PutObjectAcl` and `s3:ListBucket` on the access point and its `/object/*` path, and the `NullifyS3Bucket` grants stay.

```bash
    ParameterKey=NullifyS3AccessPointArn,ParameterValue=arn:aws:s3:REGION:NULLIFY-ACCOUNT:accesspoint/NAME \
```

On an existing stack, add that line to the `update-stack` command above.

### Stack outputs

| Output | Value |
|---|---|
| `RoleArn`, `IAMRoleArn` | ARN of the Nullify read-only role |
| `RoleName` | `AWSIntegration-<CustomerName>-NullifyReadOnlyRole` |
| `KubernetesGroupName` | `nullify-readonly`, the default group for the managed EKS scan |
| `KMSPolicyResource` | Resources of the KMS policy, comma-separated: `NullifyKMSKeyArn` and `key/*` in its account and region (only when `NullifyKMSKeyArn` is set) |

## Managed EKS scan (no in-cluster agent)

Nullify lists Kubernetes resources in your EKS cluster from Nullify's cloud-scan compute, using the read-only role this template creates. Nothing runs in the cluster. The scan only calls `list`, on 26 kinds:

| API group | Resources |
|---|---|
| core | nodes, namespaces, pods, services, persistentvolumeclaims, persistentvolumes, configmaps, secrets, resourcequotas, limitranges, serviceaccounts |
| apps | deployments, daemonsets, statefulsets, replicasets |
| networking.k8s.io | ingresses, networkpolicies |
| discovery.k8s.io | endpointslices |
| rbac.authorization.k8s.io | roles, rolebindings, clusterroles, clusterrolebindings |
| admissionregistration.k8s.io | validatingwebhookconfigurations, mutatingwebhookconfigurations, validatingadmissionpolicies, validatingadmissionpolicybindings |

Kubernetes has no metadata-only permission for Secrets: `list secrets` permits reading values, whichever authorization mode you pick.

### In-cluster collector or managed scan

| | In-cluster collector (Helm `nullify-k8s-collector`) | Managed scan |
|---|---|---|
| Runs in the cluster | CronJob with an IRSA service account | Nothing |
| Cluster endpoint | Any, including private-only | Public endpoint that admits Nullify's egress IPs |
| AWS setup | `EnableEKSIntegration=true`, OIDC provider URL, `NullifyS3Bucket` (upload target) | One access entry per cluster |
| Kubernetes setup | Helm release | ClusterRole and binding for group `nullify-readonly`, or `AmazonEKSAdminViewPolicy` |
| Upgrades | You upgrade the chart | None |

Both can run against the same cluster.

### Prerequisites

- The main stack above is deployed. Note its `CustomerName`: the role is `AWSIntegration-<CustomerName>-NullifyReadOnlyRole`.
- The cluster's authentication mode is `API` or `API_AND_CONFIG_MAP`:
  `aws eks describe-cluster --name CLUSTER --query cluster.accessConfig.authenticationMode`.
  Switching from `CONFIG_MAP` is one-way. The script does it only with `--allow-auth-mode-change`.
- The public endpoint is enabled. Private-only clusters are not supported; use the in-cluster collector.
- The operator running setup has `eks:DescribeCluster`, `eks:DescribeUpdate`, `eks:ListUpdates`, `eks:UpdateClusterConfig`, `eks:CreateAccessEntry`, `eks:DescribeAccessEntry`, `eks:DeleteAccessEntry`, `eks:ListAccessEntries`, `eks:AssociateAccessPolicy`, `eks:ListAssociatedAccessPolicies`, `eks:TagResource`, `eks:UntagResource`, CloudFormation permissions on the access stacks, and Kubernetes cluster-admin (to create the ClusterRole and to impersonate in `verify`).
- AWS CLI v2, plus `kubectl` for RBAC mode.

### Step 1: access entries (CloudFormation)

Deploy `nullify-eks-managed-scan-access.json` once in each region that has clusters. Access entries are regional; the IAM role is global.

```bash
aws cloudformation deploy \
  --region eu-west-1 \
  --stack-name nullify-eks-managed-scan-access \
  --template-file nullify-eks-managed-scan-access.json \
  --capabilities CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    CustomerName=yourcompany \
    ClusterNames=prod-eu,staging-eu \
    KubernetesAuthorization=RBACGroup
```

- `CustomerName` must match the main stack. If the role is ever recreated, update this stack too: EKS binds an access entry to the role's unique ID, so a recreated role is not recognised.
- The template uses the `AWS::LanguageExtensions` transform, so it needs `CAPABILITY_AUTO_EXPAND`. Do not update it with `--use-previous-template`.
- Resource logical IDs drop non-alphanumeric characters, so `prod-eu` and `prodeu` collide in one stack. Put them in separate stacks.
- Removing a name from `ClusterNames` deletes that cluster's access entry.
- For many accounts or regions, use StackSets with a per-instance `ClusterNames` override. AWS documents transform support for self-managed StackSets; check service-managed (Organizations) StackSets before relying on them.
- Entries are tagged `ManagedBy=nullify-connector-cloudformation`. Without CloudFormation, the setup script creates them, tagged `ManagedBy=nullify-connector`.

### Step 2: Kubernetes authorization

**`RBACGroup` (default).** The access entry carries group `nullify-readonly`. Bind that group to a `list`-only ClusterRole in each cluster, using one of:

- `kubectl apply -f manifests/nullify-readonly-rbac.yaml` from a checkout of this repository at a commit you reviewed;
- the `nullify-k8s-readonly-access` Helm chart;
- the same manifest committed to your GitOps repository (Flux, Argo CD).

**`AmazonEKSAdminViewPolicy` (opt-in).** Needs no Kubernetes objects, but grants far more than the scan uses.

> [!WARNING]
> `AmazonEKSAdminViewPolicy` grants `get`, `list` and `watch` on every resource: Secrets, every custom resource, and subresources such as `pods/log`. On EKS 1.34 and earlier, `get pods/exec` is enough to exec into pods over WebSocket. Access-policy grants do not show in `kubectl auth can-i --list`. `AmazonEKSViewPolicy` is not offered: it cannot list nodes, persistent volumes, Secrets, RBAC or admission objects.

### Step 3: allow Nullify's egress IPs

Nullify connects from these IPs. Use the Nullify region that serves your tenant:

| Nullify region | Egress IPs |
|---|---|
| `ap-southeast-2` | `13.55.32.104`, `3.105.146.106`, `13.211.99.100` |
| `eu-central-1` | `18.198.60.231`, `18.157.227.250`, `18.185.152.197` |
| `us-east-2` | `52.15.146.50`, `16.58.40.80`, `3.133.15.210` |

`aws eks update-cluster-config` replaces `publicAccessCidrs` rather than appending to it, so the script merges:

- a list that contains `0.0.0.0/0` is left unchanged;
- otherwise the missing `/32`s are appended, the result is refused above the EKS limit of 40 CIDRs, the list is re-read just before the update, and the CIDRs to add are recorded in the cluster tag `nullify-pending-cidrs` before the update and moved to `nullify-added-cidrs` once it succeeds, so `remove` takes out only those;
- if a run stops between the two (timeout, Ctrl-C, expired credentials), the next `apply` or `remove` treats the pending CIDRs that `publicAccessCidrs` holds as added and drops the rest. Both first check `aws eks list-updates` and stop, leaving the pending record, while an `EndpointAccessUpdate` is still `InProgress`, because the cluster can report `ACTIVE` before the update lands;
- the records use up to two cluster tags at once, so `apply` stops before changing `publicAccessCidrs` when the cluster has fewer free tags than it needs under the EKS limit of 50 tags per resource (`aws:` tags do not count);
- a record longer than an EKS tag value (256 characters) continues in `nullify-added-cidrs-2`, `nullify-added-cidrs-3`, and so on.

### Setup script

`../scripts/setup-eks-managed-scan.sh` does steps 1 (unless `--skip-access-entry`), 2 and 3 for one cluster, and verifies the result:

```bash
cd aws-integration-setup/scripts

# Print every change; make none
./setup-eks-managed-scan.sh plan --cluster prod-eu --region eu-west-1 \
  --customer-name yourcompany --nullify-region eu-central-1 --skip-access-entry

./setup-eks-managed-scan.sh apply --cluster prod-eu --region eu-west-1 \
  --customer-name yourcompany --nullify-region eu-central-1 --skip-access-entry

./setup-eks-managed-scan.sh verify --cluster prod-eu --region eu-west-1 \
  --customer-name yourcompany --nullify-region eu-central-1
```

Other flags: `--role-arn` instead of `--customer-name`, `--authorization rbac|admin-view`, `--group`, `--allow-auth-mode-change`, `--kube-context NAME` (use an existing kubeconfig context instead of a temporary one), `--rbac-manifest PATH|URL` (default: `manifests/nullify-readonly-rbac.yaml` from this checkout, or the same file at release tag `nullify-k8s-readonly-access-v0.1.0` when the checkout lacks it; if that tag's file cannot be fetched the run stops and asks for `--rbac-manifest`), `--skip-rbac` when Helm or GitOps applies RBAC, `--skip-network`, and `--dry-run` with `apply` or `remove`. `--help` lists them all.

### Step 4: verify

`setup-eks-managed-scan.sh verify` checks that:

- the authentication mode supports access entries, and the access entry exists with the group (RBAC) or a cluster-scoped `AmazonEKSAdminViewPolicy` association;
- `kubectl auth can-i list <resource> --all-namespaces --as nullify-verify --as-group nullify-readonly` answers `yes` for all 26 resources, and `create pods` does not;
- `publicAccessCidrs` admits Nullify's egress IPs.

`can-i` exercises Kubernetes RBAC only. It cannot see access-policy grants or prove that Nullify can reach the endpoint. Finish by confirming the cluster connects on the Nullify configure page.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `401 Unauthorized` | No access entry, an entry for a since-recreated role, or `CONFIG_MAP` authentication mode |
| `403 ... cannot list <resource>` | RBAC missing or incomplete for that resource |
| Timeout connecting to the endpoint | Nullify's IPs are not in `publicAccessCidrs`, or the endpoint is private-only |
| KMS `AccessDenied` on collector upload | `NullifyKMSKeyArn` is empty or not the value shown on the configure page. If it matches, the role already allows `key/*` in that account and region, so the denial comes from Nullify's key policy: contact Nullify support |

### Removal

Remove in this order so no access entry outlives the role:

1. For each cluster: `./setup-eks-managed-scan.sh remove --cluster CLUSTER --region REGION --customer-name yourcompany`. It deletes the RBAC manifest's objects, access entries tagged `ManagedBy=nullify-connector`, and only the CIDRs recorded in `nullify-added-cidrs` plus any in `nullify-pending-cidrs` that `publicAccessCidrs` still holds. It refuses to leave `publicAccessCidrs` empty, and refuses to settle `nullify-pending-cidrs` while an `EndpointAccessUpdate` of the cluster is still `InProgress` (re-run once it finishes). If the public endpoint has since been disabled, it leaves the endpoint settings, `publicAccessCidrs` and both tags alone and says so; `publicAccessCidrs` can still hold Nullify's CIDRs when the endpoint is re-enabled, so re-run `remove` then. It skips RBAC objects labelled `app.kubernetes.io/managed-by: Helm`; pass `--skip-rbac` when Helm or GitOps (Flux, Argo CD) owns the RBAC.
2. In each region: `aws cloudformation delete-stack --region REGION --stack-name nullify-eks-managed-scan-access`.
3. Delete the main stack.

`../scripts/cleanup.sh --method cloudformation --stack-name nullify-aws-integration --region <stack-region> --eks-access-regions eu-west-1,us-east-1` does steps 2 and 3 in that order. Without `--region`, the main stack is looked up in the AWS CLI's configured region.