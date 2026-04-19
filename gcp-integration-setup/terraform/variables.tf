variable "customer_name" {
  description = "Short identifier for your organisation. Used by Nullify support to correlate requests with this install."
  type        = string
}

variable "host_project_id" {
  description = "GCP project that owns the Nullify service account, workload identity pool and (when no organization_id is provided) the project-level custom role. Typically a dedicated security project."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.host_project_id))
    error_message = "host_project_id must be 6-30 chars, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "scope" {
  description = "Granularity of access. \"organization\" grants the read role on every project in the org (recommended). \"folder\" grants only on every project under the given folder. \"projects\" grants only on the project_ids list."
  type        = string
  default     = "organization"
  validation {
    condition     = contains(["organization", "folder", "projects"], var.scope)
    error_message = "scope must be one of \"organization\", \"folder\", or \"projects\"."
  }
}

variable "organization_id" {
  description = "Numeric GCP organization ID. Required when scope = \"organization\" or scope = \"folder\". Strongly recommended for scope = \"projects\" with multiple projects, because the long-tail custom role must be defined at the org to be assignable across projects."
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Numeric GCP folder ID (without the `folders/` prefix). Required when scope = \"folder\"."
  type        = string
  default     = ""
}

variable "project_ids" {
  description = "List of project IDs to grant access on. Required when scope = \"projects\"."
  type        = list(string)
  default     = []
}

variable "nullify_oidc_issuer_uri" {
  description = "Nullify's OIDC issuer URL (e.g. https://gcp.nullify.ai for prod). Provided in the Nullify console under Settings -> Cloud Integrations -> GCP."
  type        = string
  validation {
    condition     = startswith(var.nullify_oidc_issuer_uri, "https://") && !endswith(var.nullify_oidc_issuer_uri, "/")
    error_message = "nullify_oidc_issuer_uri must start with https:// and not end with a trailing slash."
  }
}

variable "nullify_tenant_id" {
  description = "Your Nullify tenant id. Provided in the Nullify console under Settings -> Cloud Integrations -> GCP. Pinned in the workload identity provider's attribute_condition so this pool only accepts subject tokens minted for this tenant."
  type        = string
  validation {
    condition     = length(var.nullify_tenant_id) > 0 && length(var.nullify_tenant_id) <= 100 && can(regex("^[A-Za-z0-9_-]+$", var.nullify_tenant_id))
    error_message = "nullify_tenant_id must be 1-100 characters of [A-Za-z0-9_-]."
  }
}

variable "wif_pool_id" {
  description = "ID for the Workload Identity Pool that will be created."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "wif_provider_id" {
  description = "ID for the Workload Identity Provider."
  type        = string
  default     = "nullify-oidc"
}

variable "service_account_name" {
  description = "Name of the customer-side service account Nullify impersonates."
  type        = string
  default     = "nullify-cloud-connector"
}
