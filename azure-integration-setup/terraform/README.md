# Nullify Azure Cloud Connector — Terraform

Provisions read-only access to your Azure environment for the Nullify Cloud
Connector, using Workload Identity Federation (WIF).

## What this provisions

- An **Entra application registration** + **service principal** Nullify
  authenticates as.
- A **federated identity credential** on that application, pinned to Nullify's
  OIDC issuer and to your specific Nullify tenant id (via the credential
  subject `nullify-tenant:<tenant_id>`).
- A single **built-in Reader** role assignment, at either a management group
  (recommended — inherited by every subscription underneath) or on a list of
  specific subscriptions.

## Optional: Entra directory read

The built-in Reader role covers every ARM-plane resource, **including RBAC role
assignments**. It grants nothing on the Microsoft Graph plane, so Nullify's
Entra directory processors (service principals, applications, users, groups,
credential expiry) and its conditional-access-policy processor read nothing and
degrade to a no-op.

Set `enable_directory_read = true` to additionally grant the connector two
admin-consented Microsoft Graph application permissions:

| Permission           | Enables                                                                  |
| -------------------- | ------------------------------------------------------------------------ |
| `Directory.Read.All` | Entra service principals, applications, users, groups, credential-expiry |
| `Policy.Read.All`    | Conditional access policies                                              |

This is **opt-in and default-off**. `Directory.Read.All` is a tenant-wide
directory read — a materially larger grant than ARM Reader — and consenting to
it requires a **Global Administrator** (or Privileged Role Administrator). If
you only want cloud-resource and RBAC coverage, leave it off.

## Authentication mode

This module provisions **workload identity federation (WIF)** — the app carries
a federated credential trusting Nullify's OIDC issuer, and **no client secret or
certificate is created**. WIF is the recommended mode: there is no long-lived
credential to store, rotate, or leak, and access is revoked by deleting the
federated credential.

Nullify also supports a **service principal** auth mode (a client secret on the
same app). This module deliberately does **not** provision that secret: a
Terraform-managed secret would live in Terraform state and `terraform output`,
reintroducing exactly the secret-handling burden WIF removes. If your
environment cannot use federation, create a client secret on the application
yourself (Entra portal → the app → Certificates & secrets, or
`az ad app credential reset`), then select **Service Principal** mode in the
Nullify console and paste the secret there. The app, service principal, and
Reader role this module creates are used unchanged for both modes — only the
credential type on the app differs.

## Prerequisites

### Installer-side permissions

The operator running `terraform apply` needs, in the target Entra tenant:

- **Application Administrator** (or equivalent) to create the app registration,
  service principal, and federated credential.
- **User Access Administrator** or **Owner** on the target management group or
  subscriptions to create the Reader role assignment.

Authenticate with `az login` before running Terraform; both providers pick up
the az CLI session.

## Quick start

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

Paste the `entra_tenant_id` and `application_client_id` outputs into the Nullify
console under **Settings → Cloud Integrations → Azure**, set the auth mode to
**Workload Identity Federation**, then click **Verify** and **Save**.

## Required inputs

| Input                     | Description                                                               |
| ------------------------- | ------------------------------------------------------------------------- |
| `customer_name`           | Short identifier for your org; appended to the app display name.          |
| `scope`                   | `management_group` (recommended) or `subscriptions`.                      |
| `management_group_id`     | Management group ID. Required for `management_group` scope.               |
| `subscription_ids`        | Subscription GUIDs. Required for `subscriptions` scope.                   |
| `nullify_oidc_issuer_url` | Nullify OIDC issuer (from the console).                                   |
| `nullify_tenant_id`       | **Raw** Nullify tenant id — the module adds the `nullify-tenant:` prefix. |

## Revoking access

Run `terraform destroy` from the `terraform/` directory. This removes the
federated credential, the application/service principal, and the role
assignment. Access is revoked immediately.

## Troubleshooting

- **Verification fails in the console** — confirm the `federated_credential_subject`
  output matches the subject Nullify expects (`nullify-tenant:<your tenant id>`).
  Pasting the prefixed value into `nullify_tenant_id` (double-prefixing) or a
  wrong tenant id is the most common cause; auth fails silently on a subject
  mismatch.
- **`RoleAssignmentExists`** on re-apply — a Reader assignment for this principal
  already exists at that scope; import it or remove the stale one.
