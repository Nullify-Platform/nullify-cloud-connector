{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "k8s-collector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "k8s-collector.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "k8s-collector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k8s-collector.labels" -}}
helm.sh/chart: {{ include "k8s-collector.chart" . }}
{{ include "k8s-collector.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8s-collector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8s-collector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "k8s-collector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "k8s-collector.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace of every namespaced object: serviceAccount.namespace, or the release
namespace when that is empty.
*/}}
{{- define "k8s-collector.namespace" -}}
{{- default .Release.Namespace .Values.serviceAccount.namespace -}}
{{- end }}

{{/*
AWS region of the Nullify bucket. S3 only accepts an SSE-KMS key from the
bucket's own region, so the key ARN's region is the default and any other value
is rejected. Call after "k8s-collector.validateCollector".
*/}}
{{- define "k8s-collector.awsRegion" -}}
{{- $keyRegion := index (splitList ":" .Values.collector.kms.keyArn) 3 -}}
{{- $region := .Values.collector.aws.region | default $keyRegion -}}
{{- if ne $region $keyRegion -}}
{{- fail (printf "collector.aws.region %q does not match the region of collector.kms.keyArn (%q). It must be the region of the Nullify S3 bucket, which is the key's region; leave it empty to use the key's region. An upgrade from chart 0.2.0 with --reuse-values carries that chart's default us-east-1: upgrade with --reset-then-reuse-values, or set collector.aws.region to the key's region." $region $keyRegion) -}}
{{- end -}}
{{- $region -}}
{{- end }}

{{/*
Rejects missing or placeholder values the CronJob cannot run without.
*/}}
{{- define "k8s-collector.validateCollector" -}}
{{- $provider := .Values.cloudProvider | default "aws" -}}
{{- if not (has $provider (list "aws" "gcp")) -}}
{{- fail (printf "cloudProvider must be \"aws\" or \"gcp\", got %q" $provider) -}}
{{- end -}}
{{- $cluster := required "collector.clusterName is required: set it to the exact cluster name, which becomes the S3 key and is matched against your cloud inventory" .Values.collector.clusterName -}}
{{- if eq $cluster "YOUR-CLUSTER-NAME" -}}
{{- fail "collector.clusterName is still the placeholder YOUR-CLUSTER-NAME: set it to the exact cluster name" -}}
{{- end -}}
{{- $bucket := required "collector.s3.bucket is required: use the bucket shown on the Nullify configure page" .Values.collector.s3.bucket -}}
{{- if eq $bucket "YOUR-NULLIFY-S3-BUCKET" -}}
{{- fail "collector.s3.bucket is still the placeholder YOUR-NULLIFY-S3-BUCKET: use the bucket shown on the Nullify configure page" -}}
{{- end -}}
{{- $keyArn := required "collector.kms.keyArn is required: the collector refuses to upload without KMS encryption" .Values.collector.kms.keyArn -}}
{{- if not (regexMatch "^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/.+" $keyArn) -}}
{{- fail (printf "collector.kms.keyArn must be a KMS key ARN (arn:aws:kms:<region>:<account-id>:key/<key-id>), got %q. A KMS alias does not work: IAM policies ignore alias ARNs for key operations, so the upload is denied kms:GenerateDataKey. Use the KMS key ARN from the Nullify configure page; if it shows an alias, contact Nullify." $keyArn) -}}
{{- end -}}
{{- if eq $provider "gcp" -}}
{{- $_ := required "collector.gke.awsRoleArn is required when cloudProvider is gcp: Nullify provides it after you register the cluster's OIDC issuer" (.Values.collector.gke.awsRoleArn | default .Values.collector.gke.nullifyAwsRoleArn) -}}
{{- end -}}
{{- end }}
