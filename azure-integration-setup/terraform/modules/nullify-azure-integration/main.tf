# Nullify Azure Cloud Connector
#
# This module provisions read-only access to an Azure environment for the
# Nullify Cloud Connector. The trust model is Workload Identity Federation
# (WIF) with OIDC as the source -- Nullify acts as an OpenID Connect identity
# provider, minting a per-tenant RS256 JWT whose `sub` claim is
# `nullify-tenant:<tenant_id>`. Entra exchanges that subject token for a
# short-lived access token on the application this module creates, then that
# token is used with the built-in Reader role to enumerate resources.
#
# No client secret or certificate is minted by this module. The only trust
# anchor is the federated identity credential, which is pinned to Nullify's
# OIDC issuer AND to this customer's specific Nullify tenant id via the
# subject. Unlike GCP's provider there is no separate attribute-condition
# layer: Entra matches the token `sub` against the credential `subject`
# EXACTLY, so the subject IS the per-tenant isolation. A wrong or unprefixed
# subject is a silent auth failure, never a security downgrade.
#
# Access is read-only: the single role granted is the built-in Reader role,
# which carries no data-plane permissions (no blob contents, no key vault
# secret values, no database rows). The customer can revoke access at any time
# by deleting the application, the federated credential, or the role
# assignment (`terraform destroy` removes all three).

locals {
  # The federated credential subject Nullify's minted token must carry. The
  # `nullify-tenant:` prefix is applied HERE, exactly once -- the customer
  # supplies the raw tenant id. This is the single per-tenant isolation
  # boundary; getting it wrong fails auth silently.
  federated_subject = "nullify-tenant:${var.nullify_tenant_id}"

  application_display_name = "${var.application_name}-${var.customer_name}"
}

# ---------------------------------------------------------------------------
# Input validation that needs to look at multiple variables. Per-variable
# `validation` blocks can't reference other vars, so a no-op terraform_data
# resource with `precondition` checks handles the scope/id pairing.
# ---------------------------------------------------------------------------

resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition     = var.scope != "management_group" || var.management_group_id != ""
      error_message = "scope = \"management_group\" requires management_group_id to be set."
    }
    precondition {
      condition     = var.scope != "subscriptions" || length(var.subscription_ids) > 0
      error_message = "scope = \"subscriptions\" requires subscription_ids to be non-empty."
    }
  }
}

# ---------------------------------------------------------------------------
# Entra application + service principal Nullify authenticates as. No secret.
# ---------------------------------------------------------------------------

resource "azuread_application" "nullify_cloud_connector" {
  display_name = local.application_display_name
  description  = "Read-only application Nullify authenticates as via Workload Identity Federation. Managed by Terraform."
}

resource "azuread_service_principal" "nullify_cloud_connector" {
  client_id   = azuread_application.nullify_cloud_connector.client_id
  description = "Service principal for the Nullify Cloud Connector application."
}

# ---------------------------------------------------------------------------
# Federated identity credential trusting Nullify's OIDC issuer for this
# tenant's subject only. This is the sole trust anchor -- no long-lived
# secret exists.
# ---------------------------------------------------------------------------

resource "azuread_application_federated_identity_credential" "nullify" {
  application_id = azuread_application.nullify_cloud_connector.id
  display_name   = "nullify-oidc"
  description    = "Trusts Nullify's OIDC issuer for federated access scoped to this tenant."

  # Nullify mints a signed RS256 JWT in-process and presents it as the client
  # assertion. Entra fetches the JWKS from `${issuer}/.well-known/jwks.json`
  # to verify the signature, then matches the token `sub` against `subject`.
  issuer    = var.nullify_oidc_issuer_url
  subject   = local.federated_subject
  audiences = ["api://AzureADTokenExchange"]
}

# ---------------------------------------------------------------------------
# Role assignment -- management-group scope. One Reader binding at the
# management group; Azure inherits it to every subscription underneath.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "reader_management_group" {
  count = var.scope == "management_group" ? 1 : 0
  scope = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"
  # Reference the built-in role by name, not by a hand-built role_definition_id.
  # azurerm resolves the name to the scope-qualified id and stores it
  # canonically; a hand-built tenant-relative id drifts against what Azure
  # returns and forces a needless replace-on-every-apply.
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.nullify_cloud_connector.object_id
}

# ---------------------------------------------------------------------------
# Role assignment -- per-subscription scope.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "reader_subscription" {
  for_each             = var.scope == "subscriptions" ? toset(var.subscription_ids) : toset([])
  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.nullify_cloud_connector.object_id
}
