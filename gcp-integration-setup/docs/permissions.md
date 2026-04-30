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
| `accesscontextmanager.accessPolicies.get/list` | VPC Service Controls access policies. |
| `accesscontextmanager.servicePerimeters.get/list` | VPC Service Controls perimeters. |
| `orgpolicy.policies.list` + `orgpolicy.policy.get` | Organisation policy discovery. |
| `alloydb.clusters.get/list` + `alloydb.instances.get/list` | AlloyDB topology. |
| `file.instances.get/list` | Filestore instance config. |
| `redis.instances.get/list` + `memcache.instances.get/list` | Memorystore instance config. |
| `artifactregistry.repositories.get/list` | Artifact Registry repo metadata (no image content). |
| `dns.managedZones.get/list` + `dns.resourceRecordSets.list` | Cloud DNS zone + record discovery. |
| `apigateway.gateways.get/list` + `apigateway.apis.get/list` + `apigateway.apiconfigs.get/list` | API Gateway topology. |
| `storage.buckets.get/list` + `storage.buckets.getIamPolicy` | Cloud Storage bucket settings + bucket-level IAM. No `storage.objects.*`. |
| `secretmanager.secrets.get/list` | Secret Manager: secret name, labels, replication policy, rotation config. No `secretmanager.versions.access` (payloads). |
| `bigquery.datasets.get/list` + `bigquery.tables.get/list` + `bigquery.routines.get/list` | BigQuery dataset/table/routine schema + IAM. No `bigquery.tables.getData` (rows) and no `bigquery.jobs.create` (no query execution / billing). |
| `cloudbuild.buildTriggers.get/list` | Cloud Build trigger config (repo binding, file filter, substitutions). No build logs or artifacts. |
| `batch.jobs.get/list` | Cloud Batch job spec. No task logs or output artifacts. |
| `workflows.workflows.get/list` | Cloud Workflows: workflow definitions only. **Not** `workflows.executions.*` or `workflows.stepEntries.*` — execution arguments and step inputs/outputs are runtime data. |
| `datastore.databases.list` + `datastore.databases.getMetadata` | Firestore database list + metadata. **Not** `datastore.entities.*` — document contents are runtime data. (Firestore in Native and Datastore modes share the `datastore.*` IAM family.) |
| `aiplatform.endpoints.get/list` | Vertex AI endpoint deployment config. No `aiplatform.endpoints.predict` (inference) and no model/dataset/featurestore reads. |
| `securitycenter.sources.get/list` | Security Command Center source config (which detection sources are wired up). **Not** `securitycenter.findings.*` or `securitycenter.assets.*` — finding contents are runtime data. Org-scope only; harmless no-op at project scope. |

## What Nullify cannot do

| Capability | Granted? | Why not |
| --- | --- | --- |
| Read object data from Cloud Storage | No | `roles/storage.objectViewer` is intentionally **not** granted. We only see bucket settings + bucket IAM. |
| Read secret payloads from Secret Manager | No | `roles/secretmanager.secretAccessor` is intentionally **not** granted. We only see secret names, labels, replication policy. |
| Read BigQuery table rows | No | `roles/bigquery.dataViewer` is intentionally **not** granted. We only see dataset/table schema + IAM. |
| Run BigQuery queries | No | `bigquery.jobs.create` is **not** granted. No query execution and no billable jobs. |
| Read Workflow execution payloads | No | `workflows.executions.*` and `workflows.stepEntries.*` are **not** granted. We only see workflow definitions, never the inputs/outputs of an execution. The predefined `roles/workflows.viewer` is **not** used because it would expose execution payloads. |
| Read Firestore document contents | No | `datastore.entities.*` is **not** granted. We only see the database list. The predefined `roles/datastore.viewer` is **not** used because it grants document reads. |
| Run Vertex AI inference | No | `aiplatform.endpoints.predict` and `computeTokens` are **not** granted. We see endpoint config only — not models, datasets, or featurestores. The broader `roles/aiplatform.viewer` is **not** used. |
| Read SCC findings | No | `securitycenter.findings.*` and `securitycenter.assets.*` are **not** granted. We only see which detection sources are configured. |
| Read Cloud Build logs or artifacts | No | Trigger config only. No build logs, artifacts, or source contents. |
| Read Cloud Batch task logs | No | Job spec only. No task logs or output artifacts. |
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
