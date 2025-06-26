variable "iam_role_arn" {
  type        = string
  description = "The ARN of the IAM role for the service account annotation"
}

variable "service_account_name" {
  type        = string
  description = "The name of the Kubernetes service account"
  default     = "nullify-k8s-collector-sa"
}

variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket for storing scan results"
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "The AWS region"
  default     = "ap-southeast-2"
}

variable "kubernetes_namespace" {
  type        = string
  description = "The Kubernetes namespace for Nullify resources"
  default     = "nullify"
}

variable "collector_image" {
  type        = string
  description = "Docker image for the Kubernetes collector"
  default     = "nullify/k8s-collector:latest"
}

variable "cronjob_schedule" {
  type        = string
  description = "Cron schedule for the Kubernetes collector job"
  default     = "0 0 * * *"
}

variable "kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key for key management operations (optional)"
  default     = ""
} 