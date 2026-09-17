{{- define "nullify-readonly.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nullify
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
groupName as rendered and validated: trimmed of surrounding whitespace.
*/}}
{{- define "nullify-readonly.groupName" -}}
{{- trim (toString (required "groupName is required" .Values.groupName)) -}}
{{- end }}

{{/*
Rejects a widened grant: system: subjects, default/control-plane ServiceAccounts,
aggregate-to-* and reserved label keys, extraRules verbs other than list,
wildcards, subresources other than status/scale, and any nonResourceURLs.
*/}}
{{- define "nullify-readonly.validate" -}}
{{- $group := include "nullify-readonly.groupName" . -}}
{{- if not $group -}}
{{- fail "groupName is required" -}}
{{- end -}}
{{- if hasPrefix "system:" (lower $group) -}}
{{- fail (printf "groupName %q must not start with \"system:\": binding a system group grants this access to every principal in it" $group) -}}
{{- end -}}
{{- $reservedLabels := list "helm.sh/chart" "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/managed-by" "app.kubernetes.io/part-of" -}}
{{- $aggregateLabels := list "rbac.authorization.k8s.io/aggregate-to-view" "rbac.authorization.k8s.io/aggregate-to-edit" "rbac.authorization.k8s.io/aggregate-to-admin" -}}
{{- range $key, $_ := .Values.labels -}}
{{- $labelKey := trim (toString $key) -}}
{{- if has $labelKey $aggregateLabels -}}
{{- fail (printf "labels %q is not allowed: aggregating this ClusterRole into view, edit or admin widens those built-in roles" $labelKey) -}}
{{- end -}}
{{- if has $labelKey $reservedLabels -}}
{{- fail (printf "labels %q is not allowed: this chart already sets that key" $labelKey) -}}
{{- end -}}
{{- end -}}
{{- range .Values.extraSubjects -}}
{{- $kind := trim (toString .kind) -}}
{{- $name := trim (toString .name) -}}
{{- if not (has $kind (list "User" "Group" "ServiceAccount")) -}}
{{- fail (printf "extraSubjects kind %q is not allowed: use User, Group or ServiceAccount" $kind) -}}
{{- end -}}
{{- if hasPrefix "system:" (lower $name) -}}
{{- fail (printf "extraSubjects %s %q must not start with \"system:\": system identities include anonymous callers and every-principal groups" $kind $name) -}}
{{- end -}}
{{- if eq $kind "ServiceAccount" -}}
{{- $namespace := lower (trim (toString .namespace)) -}}
{{- if or (hasPrefix "system:" $namespace) (has $namespace (list "kube-system" "kube-public" "kube-node-lease")) -}}
{{- fail (printf "extraSubjects ServiceAccount namespace %q is not allowed: control-plane namespaces run system components" $namespace) -}}
{{- end -}}
{{- if eq (lower $name) "default" -}}
{{- fail (printf "extraSubjects ServiceAccount %q is not allowed: do not bind the default ServiceAccount in any namespace" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $allowedSubresources := list "status" "scale" -}}
{{- range .Values.extraRules -}}
{{- range .verbs -}}
{{- if not (eq (toString .) "list") -}}
{{- fail (printf "extraRules verb %q is not allowed: this chart only grants list" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- range .apiGroups -}}
{{- if contains "*" (toString .) -}}
{{- fail (printf "extraRules apiGroup %q is not allowed: name each API group" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- range .resources -}}
{{- $resource := lower (trim (toString .)) -}}
{{- $parts := splitList "/" $resource -}}
{{- $allowedSubresource := and (eq (len $parts) 2) (has (last $parts) $allowedSubresources) -}}
{{- if or (contains "*" $resource) (and (gt (len $parts) 1) (not $allowedSubresource)) -}}
{{- fail (printf "extraRules resource %q is not allowed: wildcards and subresources other than status and scale reach beyond read-only configuration" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- range .nonResourceURLs -}}
{{- fail (printf "extraRules nonResourceURL %q is not allowed: this chart only grants resource list rules; /version is already granted with get" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- end }}
