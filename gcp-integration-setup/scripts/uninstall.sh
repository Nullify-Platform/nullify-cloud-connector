#!/usr/bin/env bash
# uninstall.sh — revoke the Nullify GCP Cloud Connector installed by install.sh.
#
# This is the gcloud-only counterpart to `terraform destroy`. If you used the
# Terraform module, run `terraform destroy` instead.

set -euo pipefail

: "${NULLIFY_HOST_PROJECT:?NULLIFY_HOST_PROJECT is required}"
: "${NULLIFY_ORG_ID:?NULLIFY_ORG_ID is required}"

POOL_ID="${NULLIFY_WIF_POOL_ID:-nullify-cloud-connector}"
PROVIDER_ID="${NULLIFY_WIF_PROVIDER_ID:-nullify-aws}"
SA_NAME="${NULLIFY_SA_NAME:-nullify-cloud-connector}"
SA_EMAIL="${SA_NAME}@${NULLIFY_HOST_PROJECT}.iam.gserviceaccount.com"
CUSTOM_ROLE_ID="nullifyCloudConnector"

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
  "organizations/${NULLIFY_ORG_ID}/roles/${CUSTOM_ROLE_ID}"
)

echo "==> Removing organisation IAM bindings"
for role in "${ROLES[@]}"; do
  gcloud organizations remove-iam-policy-binding "${NULLIFY_ORG_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None >/dev/null 2>&1 || true
done

echo "==> Deleting workload identity provider ${PROVIDER_ID}"
gcloud iam workload-identity-pools providers delete "${PROVIDER_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global \
  --workload-identity-pool="${POOL_ID}" --quiet 2>/dev/null || true

echo "==> Deleting workload identity pool ${POOL_ID}"
gcloud iam workload-identity-pools delete "${POOL_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global --quiet 2>/dev/null || true

echo "==> Deleting service account ${SA_EMAIL}"
gcloud iam service-accounts delete "${SA_EMAIL}" \
  --project="${NULLIFY_HOST_PROJECT}" --quiet 2>/dev/null || true

echo "==> Deleting organisation custom role ${CUSTOM_ROLE_ID}"
gcloud iam roles delete "${CUSTOM_ROLE_ID}" \
  --organization="${NULLIFY_ORG_ID}" --quiet 2>/dev/null || true

echo
echo "Nullify GCP integration uninstalled."
