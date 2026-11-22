output "application_client_id" {
  description = "Paste this into the Nullify console under Settings -> Connectors -> Azure -> Client ID."
  value       = module.nullify_azure_integration.application_client_id
}

output "entra_tenant_id" {
  description = "Paste this into the Nullify console under Settings -> Connectors -> Azure -> Tenant ID."
  value       = module.nullify_azure_integration.entra_tenant_id
}

output "federated_credential_subject" {
  description = "The exact subject Nullify's minted token must carry. Cross-check against the Nullify console if verification fails."
  value       = module.nullify_azure_integration.federated_credential_subject
}

output "next_steps" {
  description = "What to do after a successful terraform apply."
  value       = <<-EOT

    Nullify Azure integration provisioned successfully.

    Next steps:
      1. Open the Nullify console -> Settings -> Connectors -> Azure.
      2. Paste the entra_tenant_id output above into "Tenant ID".
      3. Paste the application_client_id output above into "Client ID".
      4. Ensure the auth mode is "Workload Identity Federation".
      5. In Subscriptions, select Add subscription. Enter and enable at least one subscription covered by the Terraform grant, including for management-group scope.
      6. Select "Save changes", then "Validate".

    Access is read-only (built-in Reader role) with no client secret. To revoke
    at any time, run `terraform destroy` from this directory.
  EOT
}
