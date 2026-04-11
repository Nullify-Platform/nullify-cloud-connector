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
#   export NULLIFY_AWS_PRINCIPAL_ARN="arn:aws:iam::000000000000:role/nullify-cloud-connector"
#   export NULLIFY_AWS_ACCOUNT_ID="000000000000"
#   ./install.sh
#
# Re-running this script is idempotent — every gcloud command checks for
# existing resources before creating them.

set -euo pipefail

: "${NULLIFY_HOST_PROJECT:?NULLIFY_HOST_PROJECT is required}"
: "${NULLIFY_ORG_ID:?NULLIFY_ORG_ID is required}"
: "${NULLIFY_AWS_PRINCIPAL_ARN:?NULLIFY_AWS_PRINCIPAL_ARN is required}"
: "${NULLIFY_AWS_ACCOUNT_ID:?NULLIFY_AWS_ACCOUNT_ID is required}"

POOL_ID="${NULLIFY_WIF_POOL_ID:-nullify-cloud-connector}"
PROVIDER_ID="${NULLIFY_WIF_PROVIDER_ID:-nullify-aws}"
SA_NAME="${NULLIFY_SA_NAME:-nullify-cloud-connector}"
SA_EMAIL="${SA_NAME}@${NULLIFY_HOST_PROJECT}.iam.gserviceaccount.com"

# Path-tolerant friendly name extraction. Mirrors the Terraform module's
# `nullify_aws_role_name` local. Assumed-role assertions never include a
# path so the WIF condition we pin must reference only the friendly name.
NULLIFY_ROLE_NAME="${NULLIFY_AWS_PRINCIPAL_ARN##*/}"

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

# Mirror the Terraform module's WIF attribute_condition: trust ONLY the
# Nullify AWS role, not any principal in the Nullify AWS account. Without
# this condition the pool would accept any caller from the Nullify AWS
# account, which is meaningfully weaker than the Terraform path.
ATTRIBUTE_CONDITION="attribute.aws_role == \"arn:aws:sts::${NULLIFY_AWS_ACCOUNT_ID}:assumed-role/${NULLIFY_ROLE_NAME}\""

echo "==> Creating workload identity provider ${PROVIDER_ID} (AWS source)"
gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global \
  --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-aws "${PROVIDER_ID}" \
    --project="${NULLIFY_HOST_PROJECT}" --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --account-id="${NULLIFY_AWS_ACCOUNT_ID}" \
    --attribute-mapping="google.subject=assertion.arn,attribute.account=assertion.account,attribute.aws_role=assertion.arn.contains(\"assumed-role\") ? assertion.arn.extract(\"{anything}assumed-role/\") + \"assumed-role/\" + assertion.arn.extract(\"assumed-role/{role}/\") : assertion.arn" \
    --attribute-condition="${ATTRIBUTE_CONDITION}"

echo "==> Allowing Nullify principal to impersonate the service account"
POOL_NAME="$(gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${NULLIFY_HOST_PROJECT}" --location=global --format='value(name)')"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${NULLIFY_HOST_PROJECT}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.aws_role/arn:aws:sts::${NULLIFY_AWS_ACCOUNT_ID}:assumed-role/${NULLIFY_ROLE_NAME}"

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
