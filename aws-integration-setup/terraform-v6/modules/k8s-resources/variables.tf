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
  description = "The collector's S3 upload target: the bucket name, or the S3 access point ARN Nullify provides"
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
  description = "Container image for the Kubernetes collector. Defaults to a pinned tag of Nullify's ECR Public image"
  default     = "public.ecr.aws/w4o2j2x4/integrations:k8s-collector-3.45.0"
}

variable "cronjob_schedule" {
  type        = string
  description = "Cron schedule for the Kubernetes collector job"
  default     = "0 0 * * *"
}

variable "kms_key_arn" {
  type        = string
  description = "The KMS key the collector encrypts its upload with (optional). This module only passes the value to the collector as NULLIFY_KMS_KEY_ARN, which S3 takes as SSEKMSKeyId, so every form S3 accepts is accepted here: a key ARN (including multi-Region key/mrk-... keys), an alias ARN, a bare key ID or alias/<name>. Any AWS partition"
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key/(mrk-)?[a-f0-9-]+|alias/[A-Za-z0-9/_-]+)|mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}|alias/[A-Za-z0-9/_-]+)$", var.kms_key_arn))
    error_message = "Must be empty, a KMS key ARN (arn:<partition>:kms:<region>:<account-id>:key/<key-id>), a KMS alias ARN (arn:<partition>:kms:<region>:<account-id>:alias/<name>), a bare key ID or alias/<name>"
  }
}

variable "enable_debug" {
  type        = bool
  description = "Enable debug logging for troubleshooting"
  default     = false
}
