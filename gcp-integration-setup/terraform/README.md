# Nullify GCP Cloud Connector — Terraform

Read-only access to GCP for the Nullify Cloud Connector. Workload Identity
Federation only — no service account JSON keys, no long-lived secrets.

## What this provisions

- A `google_service_account` named `nullify-cloud-connector` in the host project.
- A `google_iam_workload_identity_pool` and AWS-source provider trusting the
  Nullify AWS IAM role.
- A `google_project_iam_custom_role` with read-only permissions on the
  long-tail services that don't have a predefined viewer role (Cloud Armor,
  VPC Service Controls, AlloyDB, Filestore, Memorystore, Cloud DNS,
  API Gateway, Artifact Registry).
- IAM bindings granting the Nullify service account a curated set of
  predefined viewer roles plus the custom role above. Bound at organisation
  scope by default; per-project scope is also supported.

## What this does NOT provision

- No data-plane permissions. Nullify can list buckets but cannot read
  objects. Nullify can list secrets but cannot read secret payloads.
  Nullify can list BigQuery datasets but cannot read table rows.
- No write permissions. Nullify cannot modify your environment.
- No long-lived secrets. Revoke at any time with `terraform destroy`.

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
| `scope` | `"organization"` (recommended) or `"projects"`. |
| `organization_id` | Required when `scope = "organization"`. Find with `gcloud organizations list`. |
| `project_ids` | Required when `scope = "projects"`. List of project IDs. |
| `nullify_aws_principal_arn` | Nullify console. |
| `nullify_aws_account_id` | Nullify console. |
| `tenant_external_id` | Nullify console. |

## Permissions

See `modules/nullify-gcp-integration/main.tf` for the full list of predefined
roles + custom role permissions, with a comment next to each explaining why
Nullify needs it.

## Revoking access

```bash
terraform destroy
```

This deletes the workload identity provider, the service account and every
IAM binding in one shot.
