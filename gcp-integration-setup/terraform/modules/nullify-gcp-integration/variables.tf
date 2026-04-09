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

variable "nullify_aws_principal_arn" {
  description = "The AWS IAM role ARN that Nullify uses to call your GCP environment via Workload Identity Federation. Provided in the Nullify console; never change this value yourself."
  type        = string
  validation {
    # Allow paths in the role ARN — e.g. arn:aws:iam::000:role/path/to/Name.
    # The friendly name (everything after the last "/") is what shows up in
    # the assumed-role assertion and is what we pin the WIF condition on.
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.nullify_aws_principal_arn))
    error_message = "nullify_aws_principal_arn must be a valid AWS IAM role ARN."
  }
}

variable "nullify_aws_account_id" {
  description = "The AWS account ID Nullify operates from. Used as the audience subject in the workload identity provider attribute condition. Provided in the Nullify console."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.nullify_aws_account_id))
    error_message = "nullify_aws_account_id must be a 12 digit AWS account ID."
  }
}

variable "wif_pool_id" {
  description = "ID for the Workload Identity Pool that will be created. Must be unique within the host project."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "wif_provider_id" {
  description = "ID for the Workload Identity Provider that trusts the Nullify AWS principal. Must be unique within the pool."
  type        = string
  default     = "nullify-aws"
}

variable "service_account_name" {
  description = "Name of the customer-side service account that Nullify impersonates after the WIF token exchange."
  type        = string
  default     = "nullify-cloud-connector"
}
