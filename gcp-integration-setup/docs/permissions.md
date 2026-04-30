# GCP permissions granted to Nullify

This document explains every IAM role and custom permission the Nullify
Cloud Connector requests, and why. Use it to satisfy security review.

## Trust model

- **Workload Identity Federation (WIF)**, OIDC source.
- Nullify acts as an OpenID Connect identity provider. The JWKS document
  (`{nullify_oidc_issuer_uri}/.well-known/jwks.json`) is publicly fetched
  by Google STS to verify subject token signatures.
- Nullify never holds a long-lived service account key.
- Every API call is authenticated with a short-lived token (~1 hour) minted
  by exchanging a per-tenant RS256 JWT through your workload identity pool.
- The pool's attribute condition pins trust to your specific Nullify
  tenant id (`assertion.tenant_id == "<your tenant id>"`). Any other
  Nullify tenant's token is rejected by GCP before any permission check
  happens — so even if Nullify's signing key were stolen, an attacker
  could not mint a token accepted by another tenant's provider.

## Predefined roles

| Role | Why Nullify needs it |
| --- | --- |
| `roles/cloudasset.viewer` | Org-wide asset enumeration via Cloud Asset Inventory. The cheapest way to discover everything. |
| `roles/iam.securityReviewer` | Read all IAM bindings, custom roles, deny policies, recommendations. Drives the IAM exposure analysis. |
| `roles/compute.viewer` | VPC, instances, firewalls, load balancers, routes, NAT, peering. Drives the network topology. |
| `roles/container.clusterViewer` | GKE cluster + node pool config. |
| `roles/cloudsql.viewer` | Cloud SQL instance + replica config. |
| `roles/spanner.viewer` | Spanner instance + database config. |
| `roles/cloudkms.viewer` | KMS key ring + crypto key config (no key material). |
| `roles/logging.viewer` | Logging sink + exclusion config (no log content). |
| `roles/run.viewer` | Cloud Run service + revision config. |
| `roles/cloudfunctions.viewer` | Cloud Functions config. |
| `roles/appengine.appViewer` | App Engine service + version config. |
| `roles/dataproc.viewer` | Dataproc cluster + job config. |
| `roles/dataflow.viewer` | Dataflow job config. |
| `roles/pubsub.viewer` | Pub/Sub topic + subscription config. |

## Custom role: `nullifyCloudConnector`

Read-only permissions on services that don't have a predefined viewer role.
Strict allowlist of `*.get` / `*.list` only.

| Permission | Purpose |
| --- | --- |
| `compute.securityPolicies.get/list` | Cloud Armor WAF rule discovery. |
| `accesscontextmanager.accessPolicies.get/list` * | VPC Service Controls access policies. |
| `accesscontextmanager.servicePerimeters.get/list` * | VPC Service Controls perimeters. |
| `orgpolicy.policies.list` + `orgpolicy.policy.get` * | Organisation policy discovery. |
| `alloydb.clusters.get/list` + `alloydb.instances.get/list` | AlloyDB topology. |
| `file.instances.get/list` | Filestore instance config. |
| `redis.instances.get/list` + `memcache.instances.get/list` | Memorystore instance config. |
| `artifactregistry.repositories.get/list` | Artifact Registry repo metadata (no image content). |
| `dns.managedZones.get/list` + `dns.resourceRecordSets.list` | Cloud DNS zone + record discovery. |
| `apigateway.gateways.get/list` + `apigateway.apis.get/list` + `apigateway.apiconfigs.get/list` | API Gateway topology. |

\* Permissions marked with an asterisk are only includable in **organisation-scoped** custom roles — GCP rejects them in a project-scoped custom role because the underlying resources live at the organisation. They are silently omitted when this module is deployed without `organization_id` (single-project installs); a single-project install simply has no VPC SC or org-policy data to read.

## What Nullify cannot do

| Capability | Granted? | Why not |
| --- | --- | --- |
| Read object data from Cloud Storage | No | `roles/storage.objectViewer` is intentionally **not** granted. We only see bucket metadata. |
| Read secret payloads from Secret Manager | No | `roles/secretmanager.secretAccessor` is intentionally **not** granted. We only see secret names and metadata. |
| Read BigQuery table rows | No | `roles/bigquery.dataViewer` is intentionally **not** granted. We only see dataset metadata. |
| Modify your environment | No | Every role above is read-only. There are no write/admin roles. |
| Run code or workloads | No | No `roles/run.invoker`, `roles/cloudfunctions.invoker` etc. |

## Revoking access

```bash
cd nullify-cloud-connector/gcp-integration-setup/terraform
terraform destroy
```

Or via gcloud:

```bash
nullify-cloud-connector/gcp-integration-setup/scripts/uninstall.sh
```

Either path deletes the workload identity pool, the service account, and
every IAM binding in one shot.
