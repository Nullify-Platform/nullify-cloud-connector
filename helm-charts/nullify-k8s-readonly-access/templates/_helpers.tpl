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
Rejects values that would widen the grant beyond read-only configuration access
for the intended subjects:
- any subject named "system:..." (for example system:authenticated or
  system:anonymous), whatever its kind, compared trimmed and case-insensitively;
- ServiceAccounts in Kubernetes control-plane namespaces;
- extraRules verbs other than get, list and watch; wildcard apiGroups or
  resources; the exec, attach, portforward, proxy and log subresources; and
  nonResourceURLs other than /version.
*/}}
{{- define "nullify-readonly.validate" -}}
{{- $group := trim (toString (required "groupName is required" .Values.groupName)) -}}
{{- if not $group -}}
{{- fail "groupName is required" -}}
{{- end -}}
{{- if hasPrefix "system:" (lower $group) -}}
{{- fail (printf "groupName %q must not start with \"system:\": binding a system group grants this access to every principal in it" $group) -}}
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
{{- end -}}
{{- end -}}
{{- $blockedSubresources := list "exec" "attach" "portforward" "proxy" "log" -}}
{{- range .Values.extraRules -}}
{{- range .verbs -}}
{{- if not (has (toString .) (list "get" "list" "watch")) -}}
{{- fail (printf "extraRules verb %q is not allowed: this chart only grants get, list and watch" (toString .)) -}}
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
{{- if or (contains "*" $resource) (and (gt (len $parts) 1) (has (last $parts) $blockedSubresources)) -}}
{{- fail (printf "extraRules resource %q is not allowed: wildcards and the exec, attach, portforward, proxy and log subresources reach beyond read-only configuration" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- range .nonResourceURLs -}}
{{- if ne (trim (toString .)) "/version" -}}
{{- fail (printf "extraRules nonResourceURL %q is not allowed: only /version, which the chart already grants" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
