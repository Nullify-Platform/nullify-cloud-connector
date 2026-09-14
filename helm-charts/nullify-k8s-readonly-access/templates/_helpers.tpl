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
Rejects values that would widen the grant beyond read-only access for one group.
A "system:" group (for example system:authenticated) would hand this access to
every principal in it.
*/}}
{{- define "nullify-readonly.validate" -}}
{{- $group := required "groupName is required" .Values.groupName -}}
{{- if hasPrefix "system:" $group -}}
{{- fail (printf "groupName %q must not start with \"system:\": binding a system group grants this access to every principal in it" $group) -}}
{{- end -}}
{{- range .Values.extraSubjects -}}
{{- if and (eq (toString .kind) "Group") (hasPrefix "system:" (toString .name)) -}}
{{- fail (printf "extraSubjects group %q must not start with \"system:\": binding a system group grants this access to every principal in it" (toString .name)) -}}
{{- end -}}
{{- end -}}
{{- range .Values.extraRules -}}
{{- range .verbs -}}
{{- if not (has (toString .) (list "get" "list" "watch")) -}}
{{- fail (printf "extraRules verb %q is not allowed: this chart only grants get, list and watch" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
