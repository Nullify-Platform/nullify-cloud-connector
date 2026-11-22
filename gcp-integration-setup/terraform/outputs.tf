output "service_account_email" {
  description = "Paste this into the Nullify console under Settings -> Connectors -> GCP -> Service account email."
  value       = module.nullify_gcp_integration.service_account_email
}

output "workload_identity_provider" {
  description = "Paste this into the Nullify console under Settings -> Connectors -> GCP -> Workload identity provider."
  value       = module.nullify_gcp_integration.workload_identity_provider
}

output "next_steps" {
  description = "What to do after a successful terraform apply."
  value       = module.nullify_gcp_integration.next_steps
}

output "managed_scan_quota_apis" {
  description = "Scanner APIs managed by this configuration. This is not a live readiness check."
  value       = module.nullify_gcp_integration.managed_scan_quota_apis
}
