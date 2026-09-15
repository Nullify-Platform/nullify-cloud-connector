# nullify-k8s-readonly-access

Read-only Kubernetes RBAC for Nullify's **managed EKS scan**. Nullify reads your
cluster's configuration from Nullify's AWS account, through the cluster's public
API endpoint, using the read-only integration role you already deployed. Nothing
runs inside the cluster.

The chart installs exactly two cluster-scoped objects:

| Object | Name (default) | Grants |
|---|---|---|
| ClusterRole | `nullify-readonly` | `list` on the 26 kinds below, and `get` on the `/version` URL. No `get` or `watch` on resources, exec, logs, proxy, custom resources or writes. |
| ClusterRoleBinding | `nullify-readonly` | Binds the ClusterRole to Group `nullify-readonly` |

| API group | Kinds (verb `list`) |
|---|---|
| core | nodes, namespaces, pods, services, persistentvolumeclaims, persistentvolumes, configmaps, secrets, resourcequotas, limitranges, serviceaccounts |
| `apps` | deployments, daemonsets, statefulsets, replicasets |
| `networking.k8s.io` | ingresses, networkpolicies |
| `discovery.k8s.io` | endpointslices |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles, clusterrolebindings |
| `admissionregistration.k8s.io` | validatingwebhookconfigurations, mutatingwebhookconfigurations, validatingadmissionpolicies, validatingadmissionpolicybindings |

These are exactly the lists the scanner makes. It also reads `/version`. The
default `system:public-info-viewer` binding usually allows that, but hardened
clusters sometimes remove it, and a denied `/version` fails the whole scan, so
the ClusterRole grants `get` on `/version` itself. Clusters older than 1.30 do
not serve ValidatingAdmissionPolicies; the rule is harmless there, and the
scanner skips that kind.

The scan runs every namespace and fails the whole cluster if any of these lists
is denied, so the binding has to be cluster-wide.

## Prerequisites

- The Nullify AWS integration is deployed (CloudFormation or Terraform in this
  repository). It creates `AWSIntegration-<CustomerName>-NullifyReadOnlyRole`.
- Kubernetes 1.21 or later, and the cluster's **public** endpoint is enabled.
  Private-only clusters cannot be scanned this way; use the
  [in-cluster collector](../nullify-k8s-collector/README.md) instead.
- The cluster authentication mode includes the EKS API (`API` or
  `API_AND_CONFIG_MAP`), or you map the role in `aws-auth`.
- An identity that can create ClusterRoles, such as cluster-admin or your GitOps
  controller. Kubernetes only lets you grant permissions you already hold.

```bash
export CLUSTER=my-cluster REGION=eu-west-1 ACCOUNT_ID=123456789012 CUSTOMER_NAME=acme
export ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/AWSIntegration-${CUSTOMER_NAME}-NullifyReadOnlyRole"
export NULLIFY_GROUP=nullify-readonly
```

## 1. Map the Nullify role to the group

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.accessConfig.authenticationMode' --output text

aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$ROLE_ARN" --type STANDARD --kubernetes-groups "$NULLIFY_GROUP"
```

- Do **not** associate an EKS access policy. This chart's RBAC is the only grant.
- `update-access-entry --kubernetes-groups` **replaces** the group list. If the role already has an entry, include its existing groups.
- If the authentication mode is `CONFIG_MAP`, either switch to `API_AND_CONFIG_MAP` (one-way) or add the role to `aws-auth` `mapRoles` with `groups: [nullify-readonly]`.

## 2. Install the RBAC

Choose one of the three methods below.

### Helm

```bash
helm repo add nullify https://nullify-platform.github.io/nullify-cloud-connector/
helm repo update
helm upgrade --install nullify-k8s-readonly-access nullify/nullify-k8s-readonly-access \
  --version 0.1.0 --namespace default --set groupName="$NULLIFY_GROUP"
```

Both objects are cluster-scoped. `--namespace` only chooses where Helm stores its release record.

### Flux

Requires Flux 2.3 or later (`source.toolkit.fluxcd.io/v1`, `helm.toolkit.fluxcd.io/v2`).

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: nullify
  namespace: flux-system
spec:
  interval: 24h
  url: https://nullify-platform.github.io/nullify-cloud-connector/
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nullify-k8s-readonly-access
  namespace: flux-system
spec:
  interval: 1h
  chart:
    spec:
      chart: nullify-k8s-readonly-access
      version: "0.1.x"
      sourceRef:
        kind: HelmRepository
        name: nullify
  values:
    groupName: nullify-readonly
```

To apply the plain manifest from Git instead of using Helm:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: nullify-cloud-connector
  namespace: flux-system
spec:
  interval: 24h
  url: https://github.com/Nullify-Platform/nullify-cloud-connector
  ref:
    tag: nullify-k8s-readonly-access-v0.1.0
  ignore: |
    /*
    !/manifests/
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: nullify-readonly-access
  namespace: flux-system
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: nullify-cloud-connector
  path: ./manifests
  prune: true
```

### kubectl

[`manifests/nullify-readonly-rbac.yaml`](../../manifests/nullify-readonly-rbac.yaml)
is the chart's default render. CI fails if the manifest and the chart drift apart.
Pin a tag, never `main`:

```bash
kubectl apply -f https://raw.githubusercontent.com/Nullify-Platform/nullify-cloud-connector/nullify-k8s-readonly-access-v0.1.0/manifests/nullify-readonly-rbac.yaml
```

To move from the manifest to Helm later, let Helm adopt the two objects instead
of deleting them, so scans keep working. Helm 3.2 and later adopts an existing
object that carries its release's ownership metadata; without it, the install
fails with `invalid ownership metadata`:

```bash
# Helm CLI install above: the release name and --namespace.
export RELEASE_NAME=nullify-k8s-readonly-access RELEASE_NAMESPACE=default
# Flux HelmRelease above: spec.releaseName (default [<spec.targetNamespace>-]<metadata.name>)
# and spec.storageNamespace (default metadata.namespace), here:
# export RELEASE_NAME=nullify-k8s-readonly-access RELEASE_NAMESPACE=flux-system

kubectl label clusterrole/nullify-readonly clusterrolebinding/nullify-readonly \
  app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate clusterrole/nullify-readonly clusterrolebinding/nullify-readonly \
  meta.helm.sh/release-name="$RELEASE_NAME" \
  meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" --overwrite
```

`meta.helm.sh/release-namespace` must be the namespace Helm stores the release
in, not a namespace the objects live in (both are cluster-scoped). A mismatch
fails the install or reconcile with `invalid ownership metadata`.

Then install with that release name and namespace. If a Flux Kustomization
applied the manifest, remove it with `prune: false` first, or it deletes the
objects Helm just adopted.

## 3. Allow Nullify on the API endpoint

Add Nullify's egress IP addresses for your Nullify region to the cluster's
public access CIDRs. The region is where your Nullify tenant runs, not where the
cluster runs.

| Nullify region | Egress IPs |
|---|---|
| `ap-southeast-2` | `13.55.32.104/32`, `3.105.146.106/32`, `13.211.99.100/32` |
| `eu-central-1` | `18.198.60.231/32`, `18.157.227.250/32`, `18.185.152.197/32` |
| `us-east-2` | `52.15.146.50/32`, `16.58.40.80/32`, `3.133.15.210/32` |

Nullify will also serve this list from an API endpoint; until then this table is
the source of truth.

`publicAccessCidrs` **replaces** the list, so merge with the current value, and
the list holds at most 40 CIDRs. If the current value is `0.0.0.0/0`, the
endpoint is already open to Nullify.

```bash
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,cidrs:publicAccessCidrs}'
```

## 4. Verify

Kubernetes only accepts `--as-group` together with `--as`, so impersonate a
throwaway username that has no bindings of its own. Your identity needs
`impersonate` on users and groups (cluster-admin has it).

```bash
AS=(--as nullify-verify --as-group "$NULLIFY_GROUP")
for r in nodes namespaces persistentvolumes \
  clusterroles.rbac.authorization.k8s.io clusterrolebindings.rbac.authorization.k8s.io \
  validatingwebhookconfigurations.admissionregistration.k8s.io \
  mutatingwebhookconfigurations.admissionregistration.k8s.io \
  validatingadmissionpolicies.admissionregistration.k8s.io \
  validatingadmissionpolicybindings.admissionregistration.k8s.io; do
  printf '%-64s %s\n' "$r" "$(kubectl auth can-i list "$r" "${AS[@]}")"
done
for r in pods services persistentvolumeclaims configmaps secrets resourcequotas limitranges serviceaccounts \
  deployments.apps daemonsets.apps statefulsets.apps replicasets.apps \
  ingresses.networking.k8s.io networkpolicies.networking.k8s.io endpointslices.discovery.k8s.io \
  roles.rbac.authorization.k8s.io rolebindings.rbac.authorization.k8s.io; do
  printf '%-64s %s\n' "$r" "$(kubectl auth can-i list "$r" --all-namespaces "${AS[@]}")"
done
kubectl auth can-i get secrets --all-namespaces "${AS[@]}"      # no
kubectl auth can-i get pods/exec --all-namespaces "${AS[@]}"    # no
kubectl auth can-i create pods --all-namespaces "${AS[@]}"      # no
```

Every `list` line must print `yes`. This proves the group's RBAC only. Check
the role-to-group mapping with `aws eks describe-access-entry`, and confirm the
whole path with **Verify** in the Nullify console.

## Secrets and ConfigMaps

- Kubernetes has no metadata-only permission: `list secrets` returns Secret values to the caller.
- Nullify's checks read only a Secret's type, namespace and key names. Values are redacted before anything is stored, but the scanner process does receive them.
- `grantSecretsRead` and `grantConfigMapsRead` exist so you can withhold either kind. **Today, setting either to `false` makes the managed scan fail for the whole cluster.** Leave both `true` until Nullify confirms that the scanner treats these kinds as optional.

## Do not use EKS access policies instead

> **Warning: `AmazonEKSAdminViewPolicy` is much broader than this chart.**
> It grants `get`, `list` and `watch` on `*` resources, which also matches subresources:
>
> - every container log (`pods/log`);
> - `nodes/proxy`;
> - every custom resource;
> - a live `watch` on Secrets;
> - on EKS 1.34 and earlier, `get pods/exec`, which is enough to exec into pods over WebSocket.
>
> Access-policy permissions also do not appear in `kubectl auth can-i --list`, and
> impersonation cannot test them. Use it only if you cannot apply any in-cluster
> RBAC, and only with `--access-scope type=cluster`; a namespace-scoped association
> fails the scan.

`AmazonEKSViewPolicy` does not work. It lacks nodes, persistentvolumes, secrets,
the four RBAC kinds and the four admission kinds, so the scan fails.

## Values

| Value | Default | Description |
|---|---|---|
| `groupName` | `nullify-readonly` | Group bound to the ClusterRole. Must match the access entry's `--kubernetes-groups`. Names starting `system:` are rejected. |
| `clusterRoleName` | `nullify-readonly` | ClusterRole name |
| `clusterRoleBindingName` | `nullify-readonly` | ClusterRoleBinding name |
| `grantSecretsRead` | `true` | Include `secrets`. Required by the scan today. |
| `grantConfigMapsRead` | `true` | Include `configmaps`. Required by the scan today. |
| `extraSubjects` | `[]` | Extra binding subjects of kind `User`, `Group` or `ServiceAccount`. Any name starting `system:` (trimmed, any case) is rejected, as are ServiceAccounts in `kube-system`, `kube-public` and `kube-node-lease`. |
| `extraRules` | `[]` | Extra ClusterRole rules. Only `get`, `list` and `watch`; no wildcard `apiGroups` or `resources`; no subresources other than `status` and `scale` (so no `exec`, `log`, `proxy`, or CRD subresources such as a VM `console`); `nonResourceURLs` only `/version`. |
| `labels` | `{}` | Labels added to both objects |
| `annotations` | `{}` | Annotations added to both objects |

## Uninstall

```bash
helm uninstall nullify-k8s-readonly-access --namespace default
# or: kubectl delete clusterrolebinding,clusterrole nullify-readonly
aws eks delete-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN"
```
