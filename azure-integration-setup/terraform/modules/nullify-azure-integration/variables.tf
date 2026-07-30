variable "customer_name" {
  description = "Short identifier for your organisation. Used by Nullify support to correlate console support requests with this install. Embedded in the application's display name so it is easy to find in the Entra portal."
  type        = string
  validation {
    condition     = length(var.customer_name) >= 2 && length(var.customer_name) <= 30
    error_message = "customer_name must be between 2 and 30 characters."
  }
}

variable "scope" {
  description = "Whether Nullify should be granted read access across a whole management group (recommended for full coverage) or only on a list of specific subscriptions."
  type        = string
  default     = "management_group"
  validation {
    condition     = contains(["management_group", "subscriptions"], var.scope)
    error_message = "scope must be one of \"management_group\" or \"subscriptions\"."
  }
}

variable "management_group_id" {
  description = "Azure management group ID (the name/ID, not the display name) to grant Reader on. Required when scope = \"management_group\". Nullify then reads every subscription under this management group."
  type        = string
  default     = ""
}

variable "subscription_ids" {
  description = "List of subscription GUIDs to grant Reader on. Required when scope = \"subscriptions\"."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for s in var.subscription_ids : can(regex("^[0-9a-fA-F-]{36}$", s))])
    error_message = "each subscription_ids entry must be a 36-character subscription GUID."
  }
}

variable "nullify_oidc_issuer_url" {
  description = "Nullify's OIDC issuer URL (e.g. https://gcp.nullify.ai for prod, https://gcp.dev.nullify.ai for dev). Provided in the Nullify console under Settings -> Cloud Integrations -> Azure. Azure fetches the JWKS document from `{issuer}/.well-known/jwks.json` to verify the federated subject token signature. The host is `gcp.*` because Nullify runs one shared OIDC signer per environment across all clouds."
  type        = string
  validation {
    condition     = startswith(var.nullify_oidc_issuer_url, "https://") && !endswith(var.nullify_oidc_issuer_url, "/")
    error_message = "nullify_oidc_issuer_url must start with https:// and not end with a trailing slash."
  }
}

variable "nullify_tenant_id" {
  description = "Your Nullify tenant id (raw, e.g. GitHub-1234567). Provided in the Nullify console under Settings -> Cloud Integrations -> Azure. This module prefixes it with `nullify-tenant:` to form the federated credential subject; paste the RAW value here, not the prefixed form. Azure matches the incoming token's `sub` claim against this subject EXACTLY, so a wrong or unprefixed value is a silent auth failure."
  type        = string
  validation {
    condition     = length(var.nullify_tenant_id) > 0 && length(var.nullify_tenant_id) <= 100 && can(regex("^[A-Za-z0-9_-]+$", var.nullify_tenant_id))
    error_message = "nullify_tenant_id must be 1-100 characters of [A-Za-z0-9_-]. Paste the raw tenant id; do not include the nullify-tenant: prefix."
  }
}

variable "application_name" {
  description = "Display name for the Entra application registration Nullify authenticates as. The customer_name is appended so multiple installs are distinguishable in the Entra portal."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "enable_directory_read" {
  description = "Opt-in Phase 2. When true, grants the connector's service principal the Microsoft Graph application permissions Directory.Read.All and Policy.Read.All (admin-consented) so Nullify can enumerate the Entra directory (service principals, applications, users, groups, credential expiry) and conditional access policies. Default false: the base grant is ARM Reader only. Enabling this requires a Global Administrator to consent and is a tenant-wide directory read -- a materially larger grant than Reader."
  type        = bool
  default     = false
}
