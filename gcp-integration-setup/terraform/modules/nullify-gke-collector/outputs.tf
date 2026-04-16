output "service_account_email" {
  description = "Email of the GCP service account. Use this as the iam.gke.io/gcp-service-account annotation in the Helm chart values."
  value       = google_service_account.collector.email
}

output "service_account_unique_id" {
  description = "Unique ID (21-digit number) of the GCP service account. Share this with Nullify so it can be added to the federated AWS IAM role's trust-policy allowlist."
  value       = google_service_account.collector.unique_id
}
