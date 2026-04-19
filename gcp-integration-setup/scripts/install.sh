#!/usr/bin/env bash
# install.sh — gcloud-only installer for the Nullify GCP Cloud Connector.
#
# This is an organisation-scope alternative to the Terraform module under
# ../terraform. Use it when you want to provision read-only Nullify access
# without Terraform. Folder and project scopes are NOT supported here —
# use the Terraform module for those modes.
#
# Usage:
#   export NULLIFY_HOST_PROJECT="acme-security"
#   export NULLIFY_ORG_ID="123456789012"
#   export NULLIFY_OIDC_ISSUER_URI="https://gcp.nullify.ai"
#   export NULLIFY_TENANT_ID="Nullify-XXXXXXXXXXXX"
#   ./install.sh
#
# Re-running this script is idempotent — every gcloud command checks for
# existing resources before creating them.

set -euo pipefail

: "${NULLIFY_HOST_PROJECT:?NULLIFY_HOST_PROJECT is required}"
: "${NULLIFY_ORG_ID:?NULLIFY_ORG_ID is required}"
: "${NULLIFY_OIDC_ISSUER_URI:?NULLIFY_OIDC_ISSUER_URI is required (e.g. https://gcp.nullify.ai)}"
: "${NULLIFY_TENANT_ID:?NULLIFY_TENANT_ID is required (copy from the Nullify console)}"

POOL_ID="${NULLIFY_WIF_POOL_ID:-nullify-cloud-connector}"
PROVIDER_ID="${NULLIFY_WIF_PROVIDER_ID:-nullify-oidc}"
SA_NAME="${NULLIFY_SA_NAME:-nullify-cloud-connector}"
SA_EMAIL="${SA_NAME}@${NULLIFY_HOST_PROJECT}.iam.gserviceaccount.com"

# Required APIs on the host project. Without these enabled, the WIF pool /
# provider / service account creation calls fail with cryptic 403s. Mirrors
# `apis.tf` in the Terraform module.
echo "==> Enabling required Google Cloud APIs on ${NULLIFY_HOST_PROJECT}"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudasset.googleapis.com \
  serviceusage.googleapis.com \
  --project="${NULLIFY_HOST_PROJECT}"

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

# Pin trust to this specific Nullify tenant. Nullify's OIDC issuer is
# multi-tenant; the JWT carries a `tenant_id` custom claim. Without this
# condition any Nullify tenant could exchange a token against this provider.
ATTRIBUTE_CONDITION="assertion.tenant_id == \"${NULLIFY_TENANT_ID}\""

echo "==> Creating workload identity provider ${PROVIDER_ID} (OIDC source)"
gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global \
  --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
    --project="${NULLIFY_HOST_PROJECT}" --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --issuer-uri="${NULLIFY_OIDC_ISSUER_URI}" \
    --attribute-mapping="google.subject=assertion.sub,attribute.tenant_id=assertion.tenant_id" \
    --attribute-condition="${ATTRIBUTE_CONDITION}"

echo "==> Allowing the Nullify tenant principal to impersonate the service account"
POOL_NAME="$(gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global --format='value(name)')"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${NULLIFY_HOST_PROJECT}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.tenant_id/${NULLIFY_TENANT_ID}"

# Custom role for the long-tail permissions Nullify needs that are not
# covered by predefined viewer roles. Mirrors locals.custom_role_permissions
# in the Terraform module. Defined at the organisation so it's assignable
# anywhere in the hierarchy.
CUSTOM_ROLE_ID="nullifyCloudConnector"
CUSTOM_ROLE_TITLE="Nullify Cloud Connector (read-only)"
CUSTOM_ROLE_DESCRIPTION="Read-only access to security-relevant config Nullify needs that is not covered by predefined viewer roles."

# shellcheck disable=SC2089
CUSTOM_ROLE_PERMISSIONS="compute.securityPolicies.get,compute.securityPolicies.list,accesscontextmanager.accessPolicies.get,accesscontextmanager.accessPolicies.list,accesscontextmanager.servicePerimeters.get,accesscontextmanager.servicePerimeters.list,orgpolicy.policies.list,orgpolicy.policy.get,alloydb.clusters.get,alloydb.clusters.list,alloydb.instances.get,alloydb.instances.list,file.instances.get,file.instances.list,redis.instances.get,redis.instances.list,memcache.instances.get,memcache.instances.list,artifactregistry.repositories.get,artifactregistry.repositories.list,dns.managedZones.get,dns.managedZones.list,dns.resourceRecordSets.list,apigateway.gateways.get,apigateway.gateways.list,apigateway.apis.get,apigateway.apis.list,apigateway.apiconfigs.get,apigateway.apiconfigs.list"

echo "==> Creating organisation custom role ${CUSTOM_ROLE_ID}"
if gcloud iam roles describe "${CUSTOM_ROLE_ID}" --organization="${NULLIFY_ORG_ID}" >/dev/null 2>&1; then
  gcloud iam roles update "${CUSTOM_ROLE_ID}" \
    --organization="${NULLIFY_ORG_ID}" \
    --title="${CUSTOM_ROLE_TITLE}" \
    --description="${CUSTOM_ROLE_DESCRIPTION}" \
    --permissions="${CUSTOM_ROLE_PERMISSIONS}" \
    --stage=GA >/dev/null
else
  gcloud iam roles create "${CUSTOM_ROLE_ID}" \
    --organization="${NULLIFY_ORG_ID}" \
    --title="${CUSTOM_ROLE_TITLE}" \
    --description="${CUSTOM_ROLE_DESCRIPTION}" \
    --permissions="${CUSTOM_ROLE_PERMISSIONS}" \
    --stage=GA >/dev/null
fi

echo "==> Granting predefined viewer roles at the organisation"
ROLES=(
  roles/cloudasset.viewer
  roles/iam.securityReviewer
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
