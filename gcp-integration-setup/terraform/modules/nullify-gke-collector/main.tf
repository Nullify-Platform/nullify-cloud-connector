# Nullify GKE Collector — customer-side GCP resources
#
# This module creates the minimal GCP resources a customer needs so the
# Nullify k8s-collector running inside a GKE cluster can authenticate to
# Nullify's AWS backend via Workload Identity Federation.
#
# The authentication flow:
#
#   1. GKE Workload Identity projects a Google-signed ServiceAccount ID
#      token into the collector pod (audience: sts.amazonaws.com).
#   2. The collector calls AWS sts:AssumeRoleWithWebIdentity, presenting
#      that Google-signed token plus the Nullify-owned federated IAM role ARN.
#   3. AWS validates the token against the accounts.google.com OIDC provider
#      and checks that the token's `sub` claim (the GCP SA unique ID) is in
#      the federated role's trust-policy allowlist.
#   4. AWS returns short-lived credentials scoped to s3:PutObject on the
#      k8s-collector/ prefix — the collector uploads cluster metadata and
#      exits.
#
# No long-lived AWS credential is ever stored in the customer cluster, and
# the GCP service account this module creates does NOT need any GCP IAM
# roles — it is purely an OIDC identity anchor whose signed token AWS STS
# trusts.
#
# Prerequisites:
#   - GKE Workload Identity must be enabled on the cluster
#     (--workload-pool=PROJECT.svc.id.goog). This module does NOT enable
#     it; it is a cluster-level setting the customer manages.
#
# After applying:
#   1. Share the `service_account_unique_id` output with Nullify. Nullify
#      adds it to the federated IAM role's trust-policy allowlist and
#      returns the role ARN.
#   2. Deploy the nullify-k8s-collector Helm chart with cloudProvider=gcp
#      and the values shown in the outputs.

# ---------------------------------------------------------------------------
# Service account — the OIDC identity the collector pod assumes via
# Workload Identity. No GCP IAM roles are attached; its only purpose is
# to sign an ID token that AWS STS will validate.
# ---------------------------------------------------------------------------

resource "google_service_account" "collector" {
  project      = var.project_id
  account_id   = var.service_account_name
  display_name = "Nullify Kubernetes Collector"
  description  = "OIDC identity anchor for the Nullify k8s-collector. Bound to the in-cluster Kubernetes ServiceAccount via Workload Identity. Managed by Terraform."
}

# ---------------------------------------------------------------------------
# Workload Identity binding — allows the Kubernetes ServiceAccount
# (running inside the GKE cluster) to impersonate the GCP service account.
#
# The `member` format is:
#   serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]
#
# where NAMESPACE and KSA_NAME must match the Helm chart's
# serviceAccount.namespace and serviceAccount.name values.
# ---------------------------------------------------------------------------

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.collector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account_name}]"
}
