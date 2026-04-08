output "service_account_email" {
  description = "Paste this into the Nullify console under Settings -> Cloud Integrations -> GCP -> Impersonated Service Account."
  value       = module.nullify_gcp_integration.service_account_email
}

output "workload_identity_provider" {
  description = "Paste this into the Nullify console under Settings -> Cloud Integrations -> GCP -> Workload Identity Provider."
  value       = module.nullify_gcp_integration.workload_identity_provider
}

output "next_steps" {
  description = "What to do after a successful terraform apply."
  value = <<-EOT

    Nullify GCP integration provisioned successfully.

    Next steps:
      1. Open the Nullify console -> Settings -> Cloud Integrations -> GCP.
      2. Paste the service_account_email output above into "Impersonated Service Account".
      3. Paste the workload_identity_provider output above into "Workload Identity Provider".
      4. Click "Verify". You should see a green check next to every project.
      5. Click "Save".

    To revoke access at any time, run `terraform destroy` from this directory.
  EOT
}
