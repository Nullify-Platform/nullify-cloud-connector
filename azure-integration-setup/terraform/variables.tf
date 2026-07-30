variable "customer_name" {
  description = "Short identifier for your organisation. Used by Nullify support to correlate requests with this install, and appended to the Entra application display name."
  type        = string
}

variable "scope" {
  description = "Granularity of access. \"management_group\" grants Reader on a management group so Nullify reads every subscription underneath (recommended). \"subscriptions\" grants Reader only on the subscription_ids list."
  type        = string
  default     = "management_group"
  validation {
    condition     = contains(["management_group", "subscriptions"], var.scope)
    error_message = "scope must be one of \"management_group\" or \"subscriptions\"."
  }
}

variable "management_group_id" {
  description = "Azure management group ID (not display name) to grant Reader on. Required when scope = \"management_group\"."
  type        = string
  default     = ""
}

variable "subscription_ids" {
  description = "List of subscription GUIDs to grant Reader on. Required when scope = \"subscriptions\"."
  type        = list(string)
  default     = []
}

variable "nullify_oidc_issuer_url" {
  description = "Nullify's OIDC issuer URL. Provided in the Nullify console under Settings -> Cloud Integrations -> Azure."
  type        = string
  validation {
    condition     = startswith(var.nullify_oidc_issuer_url, "https://") && !endswith(var.nullify_oidc_issuer_url, "/")
    error_message = "nullify_oidc_issuer_url must start with https:// and not end with a trailing slash."
  }
}

variable "nullify_tenant_id" {
  description = "Your Nullify tenant id, RAW (e.g. GitHub-1234567). Provided in the Nullify console under Settings -> Cloud Integrations -> Azure. The module prefixes it with `nullify-tenant:` to form the federated credential subject -- do NOT include the prefix here."
  type        = string
  validation {
    condition     = length(var.nullify_tenant_id) > 0 && length(var.nullify_tenant_id) <= 100 && can(regex("^[A-Za-z0-9_-]+$", var.nullify_tenant_id))
    error_message = "nullify_tenant_id must be 1-100 characters of [A-Za-z0-9_-]. Paste the raw tenant id; do not include the nullify-tenant: prefix."
  }
}

variable "application_name" {
  description = "Base display name for the Entra application registration Nullify authenticates as."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "enable_directory_read" {
  description = "When true, grants the connector Microsoft Graph Directory.Read.All + Policy.Read.All so Nullify can read the Entra directory and conditional access policies. Default false (ARM Reader only)"
  type        = bool
  default     = false
}
