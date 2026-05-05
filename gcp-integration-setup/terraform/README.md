# Nullify GCP Cloud Connector — Terraform

Read-only access to GCP for the Nullify Cloud Connector. OIDC + Workload
Identity Federation only — no service account JSON keys, no long-lived
secrets.

## What this provisions

- A `google_service_account` named `nullify-cloud-connector` in the host project.
- A `google_iam_workload_identity_pool` and an OIDC provider trusting
  Nullify's OIDC issuer URL, with an `attribute_condition` pinned to your
  specific Nullify tenant id.
- A custom role with read-only permissions on the long-tail services that
  don't have a suitable predefined viewer role (Cloud Armor, VPC Service
  Controls, AlloyDB, Filestore, Memorystore, Cloud DNS, API Gateway,
  Artifact Registry, Cloud Storage, Secret Manager, BigQuery, Cloud Build,
  Cloud Batch, Cloud Workflows, Firestore, Vertex AI, Security Command
  Center). Defined at the org for `scope = "organization" | "folder"`,
  at the project for `scope = "projects"`. Strict allowlist of `*.get` /
  `*.list` only — no data-plane reads (no object/secret/row/document
  contents, no execution payloads, no inference, no findings).
- IAM bindings granting the Nullify service account a curated set of
  predefined viewer roles plus the custom role above. Bound at organisation
  scope by default; folder and per-project scopes are also supported.
- The required Google Cloud APIs on the host project
  (`iam`, `iamcredentials`, `sts`, `cloudresourcemanager`, `cloudasset`,
  `serviceusage`).

## What this does NOT provision

- No data-plane permissions. Nullify can list buckets but cannot read
  objects. Nullify can list secrets but cannot read secret payloads.
  Nullify can list BigQuery datasets but cannot read table rows.
- No write permissions. Nullify cannot modify your environment.
- No long-lived secrets. Revoke at any time with `terraform destroy`.

## Prerequisites

### Installer-side IAM

The human / service identity running `terraform apply` needs, at minimum:

- `roles/iam.workloadIdentityPoolAdmin` — create the WIF pool + provider
- `roles/iam.serviceAccountAdmin` — create the Nullify service account
- `roles/serviceusage.serviceUsageAdmin` — enable the required APIs (on
  the host project)
- `roles/iam.organizationRoleAdmin` — only when `scope` is `organization`
  or `folder` (the long-tail custom role must be defined at the org)
- `roles/resourcemanager.organizationAdmin` or
  `roles/resourcemanager.folderAdmin` — only when granting bindings at the
  org or folder
- `roles/resourcemanager.projectIamAdmin` — when `scope = "projects"`,
  needed on **every** project listed in `project_ids` (not just
  `host_project_id`) so the module can grant the viewer + custom role
  bindings on each

If you want a least-privilege one-off install, request these roles on the
operator running the apply and revoke them afterwards.

### APIs

The Terraform module enables the required APIs for you (see `apis.tf`).
If your organisation restricts API enablement via Service Usage org
policies, ensure the following are allowlisted on the host project:
`iam.googleapis.com`, `iamcredentials.googleapis.com`, `sts.googleapis.com`,
`cloudresourcemanager.googleapis.com`, `cloudasset.googleapis.com`,
`serviceusage.googleapis.com`.

To enable them manually:

```bash
gcloud services enable \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com cloudasset.googleapis.com \
  serviceusage.googleapis.com \
  --project=YOUR_HOST_PROJECT
```

## Quick start

```bash
git clone https://github.com/Nullify-Platform/nullify-cloud-connector.git
cd nullify-cloud-connector/gcp-integration-setup/terraform

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # fill in values from the Nullify console

terraform init
terraform plan
terraform apply
```

After `apply`, copy the `service_account_email` and `workload_identity_provider`
outputs into the Nullify console under Settings -> Cloud Integrations -> GCP
and click "Verify".

## Required inputs

| Variable | Source |
| --- | --- |
| `customer_name` | You. Anything short and unique. |
| `host_project_id` | A GCP project you control. Typically a dedicated security project. |
| `scope` | `"organization"` (recommended), `"folder"`, or `"projects"`. |
| `organization_id` | Required when `scope = "organization"` or `scope = "folder"`. Find with `gcloud organizations list`. |
| `folder_id` | Required when `scope = "folder"`. |
| `project_ids` | Required when `scope = "projects"`. List of project IDs. |
| `nullify_oidc_issuer_uri` | Nullify console. Use `https://gcp.nullify.ai` for prod, `https://gcp.dev.nullify.ai` for dev. |
| `nullify_tenant_id` | Nullify console. Pinned in the WIF provider's `attribute_condition` so this pool only accepts subject tokens minted for your tenant. |

## Permissions

See `modules/nullify-gcp-integration/main.tf` for the full list of predefined
roles + custom role permissions, with a comment next to each explaining why
Nullify needs it. Full justification per role lives in
[`docs/permissions.md`](../docs/permissions.md).

## Revoking access

```bash
terraform destroy
```

This deletes the workload identity provider, the service account and every
IAM binding in one shot. Note: the prerequisite Google Cloud APIs are
intentionally NOT disabled on `destroy` (they may be in use by other
resources in your project).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Error 400: The attribute condition must reference one of the provider's claims` on `terraform apply` | Your `nullify_tenant_id` is empty or contains characters outside `[A-Za-z0-9_-]`. Re-paste from the Nullify console. |
| `Error 403: Permission 'iam.workloadIdentityPools.create' denied` | The installer is missing `roles/iam.workloadIdentityPoolAdmin` on the host project. |
| `Error: Constraint constraints/iam.workloadIdentityPoolProviders violated` | Your org policy restricts which OIDC issuers are accepted by WIF. Ask your security team to add `nullify_oidc_issuer_uri` to the allowlist. |
| `Error 403: serviceusage.services.use` | The host project doesn't allow the required APIs to be enabled. Have an org admin enable them ahead of `terraform apply` (see *Prerequisites > APIs*). |
| Verify in Nullify console returns red with `oauth2/google: status code 401: ... invalid token` | `nullify_oidc_issuer_uri` doesn't match the URL Nullify's issuer actually signs with. Re-copy from the console — `https://gcp.nullify.ai` for prod, `https://gcp.dev.nullify.ai` for dev. |
| Verify returns red with `permission denied: assertion.tenant_id == "..."` from STS | Your `nullify_tenant_id` doesn't match your actual Nullify tenant id. Re-paste from the console. |
| Verify returns red per project with `PERMISSION_DENIED` | The Nullify SA is missing `roles/iam.serviceAccountTokenCreator` (the WIF binding) or the predefined viewer roles on the project. Re-run `terraform apply`. |
| `Error: ... iam.disableServiceAccountCreation` | An org policy blocks SA creation in this project. Either drop the org policy on the host project, or have an org admin pre-create the SA and contact Nullify support to wire it up. |
