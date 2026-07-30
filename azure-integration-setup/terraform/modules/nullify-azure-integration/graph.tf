# ---------------------------------------------------------------------------
# Optional Phase 2: Microsoft Graph directory read.
#
# The base module grants only the ARM built-in Reader role, which covers every
# ARM-plane processor (subscriptions, compute, storage, NSGs, and RBAC role
# assignments). It grants NOTHING on the Microsoft Graph plane, so the Entra
# directory processors -- `entradirectory` (service principals, applications,
# users, groups, credential expiry) and `entraid` (conditional access
# policies) -- have no token scope and degrade to a no-op.
#
# Setting enable_directory_read = true grants the connector's service principal
# two Graph APPLICATION permissions and admin-consents them, so those
# processors succeed:
#   - Directory.Read.All -> users, groups, applications, service principals
#   - Policy.Read.All     -> conditional access policies
#
# This is intentionally opt-in and default-off: Directory.Read.All is a
# tenant-wide directory read, a materially larger grant than ARM Reader, and
# it requires a Global Administrator (or Privileged Role Administrator) to
# consent. Customers who only want cloud-resource + RBAC coverage never take
# on that grant.

# The first-party Microsoft Graph service principal in this tenant. Its
# app_role_ids map lets us reference Graph permissions by name instead of
# hard-coding the well-known GUIDs.
data "azuread_service_principal" "msgraph" {
  count     = var.enable_directory_read ? 1 : 0
  client_id = "00000003-0000-0000-c000-000000000000"
}

# Directory.Read.All -- read users, groups, applications, service principals.
# Feeds the `entradirectory` processor.
resource "azuread_app_role_assignment" "directory_read_all" {
  count               = var.enable_directory_read ? 1 : 0
  app_role_id         = data.azuread_service_principal.msgraph[0].app_role_ids["Directory.Read.All"]
  principal_object_id = azuread_service_principal.nullify_cloud_connector.object_id
  resource_object_id  = data.azuread_service_principal.msgraph[0].object_id
}

# Policy.Read.All -- read conditional access policies. Feeds the `entraid`
# processor.
resource "azuread_app_role_assignment" "policy_read_all" {
  count               = var.enable_directory_read ? 1 : 0
  app_role_id         = data.azuread_service_principal.msgraph[0].app_role_ids["Policy.Read.All"]
  principal_object_id = azuread_service_principal.nullify_cloud_connector.object_id
  resource_object_id  = data.azuread_service_principal.msgraph[0].object_id
}
