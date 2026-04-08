variable "customer_name" {
  description = "Short identifier for your organisation. Used as a label on every Nullify-managed resource for traceability."
  type        = string
  validation {
    condition     = length(var.customer_name) >= 2 && length(var.customer_name) <= 30
    error_message = "customer_name must be between 2 and 30 characters."
  }
}

variable "host_project_id" {
  description = "The GCP project that owns the workload identity pool, the Nullify service account and the IAM bindings. For org-wide installs this is typically a dedicated security project."
  type        = string
}

variable "scope" {
  description = "Whether Nullify should be granted read access at the organization level (recommended for full coverage) or only on a list of specific projects."
  type        = string
  default     = "organization"
  validation {
    condition     = contains(["organization", "projects"], var.scope)
    error_message = "scope must be either \"organization\" or \"projects\"."
  }
}

variable "organization_id" {
  description = "GCP organization numeric ID. Required when scope = \"organization\"."
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

variable "tenant_external_id" {
  description = "Per-tenant external identifier from the Nullify console. Embedded as a label on the WIF pool so Nullify can correlate inbound tokens with the right customer."
  type        = string
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

variable "labels" {
  description = "Additional labels to apply to every resource created by this module."
  type        = map(string)
  default     = {}
}
