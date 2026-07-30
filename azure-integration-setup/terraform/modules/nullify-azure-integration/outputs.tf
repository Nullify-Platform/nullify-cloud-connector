output "application_client_id" {
  description = "Client (application) ID of the Entra app Nullify authenticates as. Paste this into the Nullify console under Settings -> Cloud Integrations -> Azure -> Client ID."
  value       = azuread_application.nullify_cloud_connector.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal. Useful when manually inspecting role assignments via `az role assignment list`."
  value       = azuread_service_principal.nullify_cloud_connector.object_id
}

output "federated_credential_subject" {
  description = "The exact subject Nullify's minted token must carry (`nullify-tenant:<tenant_id>`). Surfaced so the value can be cross-checked against the Nullify console."
  value       = local.federated_subject
}

output "entra_tenant_id" {
  description = "The Entra directory (tenant) ID the application lives in. Paste this into the Nullify console under Settings -> Cloud Integrations -> Azure -> Directory (Tenant) ID."
  value       = data.azuread_client_config.current.tenant_id
}

output "scope" {
  description = "Echoes the scope chosen at apply time so it shows up in the plan output for auditors."
  value       = var.scope
}

output "directory_read_enabled" {
  description = "Whether Phase 2 Microsoft Graph directory read (Directory.Read.All + Policy.Read.All) was granted. When false, the entradirectory and entraid processors degrade to a no-op."
  value       = var.enable_directory_read
}
