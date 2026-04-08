#!/usr/bin/env bash
# install.sh — gcloud-only installer for the Nullify GCP Cloud Connector.
#
# This is an alternative to the Terraform module under ../terraform. Use it
# when you want to provision read-only Nullify access without Terraform.
#
# Usage:
#   export NULLIFY_HOST_PROJECT="acme-security"
#   export NULLIFY_ORG_ID="123456789012"
#   export NULLIFY_AWS_PRINCIPAL_ARN="arn:aws:iam::000000000000:role/nullify-cloud-connector"
#   export NULLIFY_AWS_ACCOUNT_ID="000000000000"
#   export NULLIFY_TENANT_EXTERNAL_ID="REPLACE_WITH_VALUE_FROM_NULLIFY_CONSOLE"
#   ./install.sh
#
# Re-running this script is idempotent — every gcloud command checks for
# existing resources before creating them.

set -euo pipefail

: "${NULLIFY_HOST_PROJECT:?NULLIFY_HOST_PROJECT is required}"
: "${NULLIFY_ORG_ID:?NULLIFY_ORG_ID is required}"
: "${NULLIFY_AWS_PRINCIPAL_ARN:?NULLIFY_AWS_PRINCIPAL_ARN is required}"
: "${NULLIFY_AWS_ACCOUNT_ID:?NULLIFY_AWS_ACCOUNT_ID is required}"
: "${NULLIFY_TENANT_EXTERNAL_ID:?NULLIFY_TENANT_EXTERNAL_ID is required}"

POOL_ID="${NULLIFY_WIF_POOL_ID:-nullify-cloud-connector}"
PROVIDER_ID="${NULLIFY_WIF_PROVIDER_ID:-nullify-aws}"
SA_NAME="${NULLIFY_SA_NAME:-nullify-cloud-connector}"
SA_EMAIL="${SA_NAME}@${NULLIFY_HOST_PROJECT}.iam.gserviceaccount.com"

echo "==> Creating service account ${SA_EMAIL}"
gcloud iam service-accounts describe "${SA_EMAIL}" --project="${NULLIFY_HOST_PROJECT}" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${NULLIFY_HOST_PROJECT}" \
    --display-name="Nullify Cloud Connector"

echo "==> Creating workload identity pool ${POOL_ID}"
gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --project="${NULLIFY_HOST_PROJECT}" --location=global \
    --display-name="Nullify Cloud Connector"

echo "==> Creating workload identity provider ${PROVIDER_ID} (AWS source)"
gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global \
  --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-aws "${PROVIDER_ID}" \
    --project="${NULLIFY_HOST_PROJECT}" --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --account-id="${NULLIFY_AWS_ACCOUNT_ID}" \
    --attribute-mapping="google.subject=assertion.arn,attribute.account=assertion.account,attribute.aws_role=assertion.arn"

echo "==> Allowing Nullify principal to impersonate the service account"
NULLIFY_ROLE_NAME="${NULLIFY_AWS_PRINCIPAL_ARN##*/}"
POOL_NAME="$(gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global --format='value(name)')"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${NULLIFY_HOST_PROJECT}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.aws_role/arn:aws:sts::${NULLIFY_AWS_ACCOUNT_ID}:assumed-role/${NULLIFY_ROLE_NAME}"

echo "==> Granting predefined viewer roles at the organisation"
ROLES=(
  roles/cloudasset.viewer
  roles/iam.securityReviewer
  roles/viewer
  roles/compute.viewer
  roles/container.clusterViewer
  roles/cloudsql.viewer
  roles/spanner.viewer
  roles/cloudkms.viewer
  roles/logging.viewer
  roles/run.viewer
  roles/cloudfunctions.viewer
  roles/appengine.appViewer
  roles/dataproc.viewer
  roles/dataflow.viewer
  roles/pubsub.viewer
)
for role in "${ROLES[@]}"; do
  gcloud organizations add-iam-policy-binding "${NULLIFY_ORG_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None >/dev/null
done

echo
echo "Nullify GCP integration installed successfully."
echo
echo "Paste these values into the Nullify console under Settings -> Cloud Integrations -> GCP:"
echo "  Service Account Email:        ${SA_EMAIL}"
echo "  Workload Identity Provider:   projects/$(gcloud projects describe "${NULLIFY_HOST_PROJECT}" --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
