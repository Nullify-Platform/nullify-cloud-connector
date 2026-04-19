variable "customer_name" {
  description = "Short identifier for your organisation. Used by Nullify support to correlate console support requests with this install. Not currently embedded as a label on any resource (GCP IAM resources don't expose `labels`)."
  type        = string
  validation {
    condition     = length(var.customer_name) >= 2 && length(var.customer_name) <= 30
    error_message = "customer_name must be between 2 and 30 characters."
  }
}

variable "host_project_id" {
  description = "The GCP project that owns the workload identity pool, the Nullify service account and (when no organization_id is provided) the project-level custom role. For org-wide installs this is typically a dedicated security project."
  type        = string
  validation {
    # GCP project ID rules: 6-30 chars, start with letter, end with
    # letter/digit, lowercase letters/digits/hyphens only.
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.host_project_id))
    error_message = "host_project_id must be 6-30 chars, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "scope" {
  description = "Whether Nullify should be granted read access at the organization level (recommended for full coverage), at the folder level, or only on a list of specific projects."
  type        = string
  default     = "organization"
  validation {
    condition     = contains(["organization", "folder", "projects"], var.scope)
    error_message = "scope must be one of \"organization\", \"folder\", or \"projects\"."
  }
}

variable "organization_id" {
  description = "GCP organization numeric ID. Required when scope = \"organization\". Strongly recommended for scope = \"folder\" and any scope = \"projects\" install whose project_ids span more than the host_project_id, because the long-tail custom role must be defined at the organisation to be assignable across projects."
  type        = string
  default     = ""
  validation {
    condition     = var.organization_id == "" || can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id, when set, must be a numeric organisation ID."
  }
}

variable "folder_id" {
  description = "GCP folder numeric ID (without the `folders/` prefix). Required when scope = \"folder\"."
  type        = string
  default     = ""
}

variable "project_ids" {
  description = "List of GCP project IDs to grant access to. Required when scope = \"projects\"."
  type        = list(string)
  default     = []
}

variable "nullify_oidc_issuer_uri" {
  description = "Nullify's OIDC issuer URL (e.g. https://gcp.nullify.ai for prod, https://gcp.dev.nullify.ai for dev). Provided in the Nullify console under Settings -> Cloud Integrations -> GCP. Google STS fetches the JWKS document from `{issuer}/.well-known/jwks.json` to verify subject token signatures."
  type        = string
  validation {
    condition     = startswith(var.nullify_oidc_issuer_uri, "https://") && !endswith(var.nullify_oidc_issuer_uri, "/")
    error_message = "nullify_oidc_issuer_uri must start with https:// and not end with a trailing slash."
  }
}

variable "nullify_tenant_id" {
  description = "Your Nullify tenant id. Provided in the Nullify console under Settings -> Cloud Integrations -> GCP. Embedded in the WIF provider's attribute_condition so the pool only accepts subject tokens minted for THIS tenant; this is the per-tenant isolation that makes the integration safe in a multi-tenant Nullify deployment."
  type        = string
  validation {
    condition     = length(var.nullify_tenant_id) > 0 && length(var.nullify_tenant_id) <= 100 && can(regex("^[A-Za-z0-9_-]+$", var.nullify_tenant_id))
    error_message = "nullify_tenant_id must be 1-100 characters of [A-Za-z0-9_-]."
  }
}

variable "wif_pool_id" {
  description = "ID for the Workload Identity Pool that will be created. Must be unique within the host project."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "wif_provider_id" {
  description = "ID for the Workload Identity Provider that trusts Nullify's OIDC issuer. Must be unique within the pool."
  type        = string
  default     = "nullify-oidc"
}

variable "service_account_name" {
  description = "Name of the customer-side service account that Nullify impersonates after the WIF token exchange."
  type        = string
  default     = "nullify-cloud-connector"
}
