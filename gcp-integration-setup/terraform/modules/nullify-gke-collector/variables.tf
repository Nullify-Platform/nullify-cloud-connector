variable "project_id" {
  description = "GCP project ID where the GKE cluster runs and where the collector service account will be created."
  type        = string
}

variable "service_account_name" {
  description = "Name of the GCP service account to create. The default matches the Helm chart's expectations."
  type        = string
  default     = "nullify-k8s-collector"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "service_account_name must be 6-30 characters, start with a letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where the Nullify k8s-collector is deployed. Must match serviceAccount.namespace in the Helm chart values."
  type        = string
  default     = "nullify"
}

variable "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount name used by the collector pods. Must match serviceAccount.name in the Helm chart values."
  type        = string
  default     = "nullify-k8s-collector-sa"
}
