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
  happens. This check trusts the tenant claim in a token signed by Nullify.
  A compromised signing key can forge that claim. Key protection, rotation
  and revocation remain required.

## Predefined roles

| Role | Why Nullify needs it |
| --- | --- |
| `roles/browser` | List folders and projects for organization and folder discovery. |
| `roles/cloudasset.viewer` | Org-wide asset enumeration via Cloud Asset Inventory. The cheapest way to discover everything. |
| `roles/compute.viewer` | VPC, instances, firewalls, load balancers, routes, NAT, peering. Drives the network topology. |
| `roles/container.clusterViewer` | GKE cluster + node pool config. |
| `roles/cloudsql.viewer` | Cloud SQL instance + replica config. |
| `roles/spanner.viewer` | Spanner instance + database config. |
| `roles/cloudkms.viewer` | KMS key ring + crypto key config (no key material). |
| `roles/run.viewer` | Cloud Run service + revision config. |
| `roles/cloudfunctions.viewer` | Cloud Functions config. |
| `roles/appengine.appViewer` | App Engine service + version config. |
| `roles/dataproc.viewer` | Dataproc cluster + job config. |
| `roles/dataflow.viewer` | Dataflow job config. |
| `roles/pubsub.viewer` | Pub/Sub topic + subscription config. |

## Custom role: `nullifyCloudConnector`

The custom role lists the additional configuration and IAM permissions the collectors use.

| Permission | Purpose |
| --- | --- |
| `logging.sinks.list`, `logging.logMetrics.list`, `logging.buckets.list` | List sink, log-based metric and log-bucket configuration. |
| `iam.serviceAccounts.list`, `iam.serviceAccountKeys.list` | List service accounts and key metadata. |
| `iam.roles.get/list` | Read custom roles and their included permissions. |
| `iam.workloadIdentityPools.list`, `iam.workloadIdentityPoolProviders.list` | List workload identity pools and their providers. |
| `resourcemanager.projects.getIamPolicy` | Read project IAM bindings and audit configurations. |
| `compute.securityPolicies.get/list` | Cloud Armor WAF rule discovery. |
| `accesscontextmanager.policies.list` + `accesscontextmanager.servicePerimeters.get/list` * | VPC Service Controls perimeters. |
| `orgpolicy.policies.list` | List policies on scanned projects. |
| `orgpolicy.policy.get` * | Read organization policies through the legacy API. |
| `alloydb.clusters.get/list` + `alloydb.instances.get/list` | AlloyDB topology. |
| `file.instances.get/list` | Filestore instance config. |
| `redis.instances.get/list` + `memcache.instances.get/list` | Memorystore instance config. |
| `artifactregistry.repositories.get/list/getIamPolicy`, `artifactregistry.dockerimages.list` | Repository configuration, IAM policies and image metadata. |
| `dns.managedZones.get/list` + `dns.resourceRecordSets.list` | Cloud DNS zone + record discovery. |
| `apigateway.gateways.get/list` + `apigateway.apis.get/list` + `apigateway.apiconfigs.get/list` | API Gateway topology. |
| `storage.buckets.get/list` + `storage.buckets.getIamPolicy` | Cloud Storage bucket settings + bucket-level IAM. No `storage.objects.*`. |
| `secretmanager.secrets.get/list/getIamPolicy` | Secret metadata, configuration and IAM policies. No `secretmanager.versions.access` (payloads). |
| `bigquery.datasets.get/getIamPolicy` + `bigquery.tables.get/list` + `bigquery.tables.getIamPolicy` + `bigquery.routines.get/list` | BigQuery dataset/table/routine schema + IAM. `bigquery.tables.getIamPolicy` is granted explicitly (separate from `bigquery.dataViewer`, which we **do not** grant because it would also expose row data). No `bigquery.tables.getData` (rows) and no `bigquery.jobs.create` (no query execution / billing). |
| `pubsub.topics.getIamPolicy`, `pubsub.subscriptions.getIamPolicy` | Topic and subscription IAM (detects topics bound to `allUsers` / `allAuthenticatedUsers`). The predefined `roles/pubsub.viewer` role grants metadata listing. |
| `batch.jobs.get/list` | Cloud Batch job spec. No task logs or output artifacts. |
| `workflows.workflows.get/list` | Cloud Workflows: workflow definitions only. **Not** `workflows.executions.*` or `workflows.stepEntries.*` — execution arguments and step inputs/outputs are runtime data. |
| `datastore.databases.list` + `datastore.databases.getMetadata` | Firestore database list + metadata. **Not** `datastore.entities.*` — document contents are runtime data. (Firestore in Native and Datastore modes share the `datastore.*` IAM family.) |
| `aiplatform.endpoints.get/list` | Vertex AI endpoint deployment config. No `aiplatform.endpoints.predict` (inference) and no model/dataset/featurestore reads. |
| `securitycenter.sources.get/list` | Security Command Center source config (which detection sources are wired up). **Not** `securitycenter.findings.*` or `securitycenter.assets.*` — finding contents are runtime data. Org-scope only; harmless no-op at project scope. |

\* The module includes these permissions only in its **organisation-defined** custom role. A single-project installation does not receive them and cannot read ancestor-organization VPC SC policies. Project organization-policy listing is included in all scopes.

Earlier installations granted `roles/logging.viewer` and
`roles/iam.securityReviewer`. Both roles can read log entries. Apply the
updated Terraform and confirm removal of both managed bindings. For
script-managed installations, rerun the installer to update the custom role,
then review and remove both legacy organization bindings from the connector
service account. The uninstall script also removes those legacy bindings.

For Cloud Logging, the installers grant access to configuration metadata. Check for roles
granted separately or inherited from an ancestor before validating effective
access. See the [Cloud Logging permissions reference](https://docs.cloud.google.com/iam/docs/roles-permissions/logging).

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
| Read Cloud Batch task logs | No | Job spec only. No task logs or output artifacts. |
| Modify your environment | No | Every role above is read-only. There are no write/admin roles. |
| Run code or workloads | No | No `roles/run.invoker`, `roles/cloudfunctions.invoker` etc. |

Cloud Build configuration is collected through Cloud Asset Inventory for trigger
and worker pool assets. No `cloudbuild.*` permission is granted, but the broad
asset viewer role also permits supported Build asset metadata. This is not a
permission boundary that excludes execution metadata. See
[Cloud Asset Inventory permissions](https://docs.cloud.google.com/asset-inventory/docs/roles-permissions#permissions)
and [supported asset types](https://docs.cloud.google.com/asset-inventory/docs/asset-types).

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
