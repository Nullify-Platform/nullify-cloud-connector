output "service_account_email" {
  description = "Email address of the service account Nullify will impersonate. Paste this into the Nullify console under Settings -> Cloud Integrations -> GCP."
  value       = google_service_account.nullify_cloud_connector.email
}

output "workload_identity_provider" {
  description = "Full resource path of the Workload Identity Provider Nullify will use to exchange AWS credentials for GCP tokens. Paste this into the Nullify console."
  value       = "projects/${data.google_project.host.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.nullify.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.nullify_aws.workload_identity_pool_provider_id}"
}

output "workload_identity_pool" {
  description = "Resource name of the Workload Identity Pool. Useful when manually inspecting the trust configuration via gcloud."
  value       = google_iam_workload_identity_pool.nullify.name
}

output "custom_role_id" {
  description = "Full ID of the custom role that grants the long-tail read permissions Nullify needs."
  value       = google_project_iam_custom_role.nullify_cloud_connector.id
}

output "scope" {
  description = "Echoes the scope chosen at apply time so it shows up in the plan output for auditors."
  value       = var.scope
}

data "google_project" "host" {
  project_id = var.host_project_id
}
