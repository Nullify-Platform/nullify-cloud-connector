variable "customer_name" {
  description = "Short identifier for your organisation. Used as a label on every Nullify-managed resource."
  type        = string
}

variable "host_project_id" {
  description = "GCP project that owns the Nullify service account, workload identity pool and IAM bindings. Typically a dedicated security project."
  type        = string
}

variable "scope" {
  description = "Granularity of access. \"organization\" grants the read role on every project in the org (recommended). \"projects\" grants only on the project_ids list."
  type        = string
  default     = "organization"
  validation {
    condition     = contains(["organization", "projects"], var.scope)
    error_message = "scope must be either \"organization\" or \"projects\"."
  }
}

variable "organization_id" {
  description = "Numeric GCP organization ID. Required when scope = organization."
  type        = string
  default     = ""
}

variable "project_ids" {
  description = "List of project IDs to grant access on. Required when scope = projects."
  type        = list(string)
  default     = []
}

variable "nullify_aws_principal_arn" {
  description = "AWS IAM role ARN that Nullify uses to call your GCP environment. Provided in the Nullify console under Settings -> Cloud Integrations -> GCP."
  type        = string
}

variable "nullify_aws_account_id" {
  description = "AWS account ID Nullify operates from. Provided in the Nullify console."
  type        = string
}

variable "tenant_external_id" {
  description = "Per-tenant external identifier from the Nullify console. Embedded as a label so Nullify can correlate inbound tokens with the right customer."
  type        = string
}

variable "wif_pool_id" {
  description = "ID for the Workload Identity Pool that will be created."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "wif_provider_id" {
  description = "ID for the Workload Identity Provider."
  type        = string
  default     = "nullify-aws"
}

variable "service_account_name" {
  description = "Name of the customer-side service account Nullify impersonates."
  type        = string
  default     = "nullify-cloud-connector"
}

variable "labels" {
  description = "Extra labels to apply to every Nullify-managed resource."
  type        = map(string)
  default     = {}
}
