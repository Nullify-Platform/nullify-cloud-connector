{{- define "k8s-collector.validateExtraRules" -}}
{{- $root := . -}}
{{- range $flag := list "grantSecretsRead" "grantConfigMapsRead" -}}
{{- if and (hasKey $root.Values $flag) (not (kindIs "bool" (index $root.Values $flag))) -}}
{{- fail (printf "%s must be a boolean" $flag) -}}
{{- end -}}
{{- end -}}
{{- range .Values.extraRules -}}
{{- if not (kindIs "map" .) -}}
{{- fail "extraRules entries must be resource rule objects" -}}
{{- end -}}
{{- range .nonResourceURLs -}}
{{- fail (printf "extraRules nonResourceURL %q is not allowed: discovery URLs are built in" (toString .)) -}}
{{- end -}}
{{- if or (not (kindIs "slice" .apiGroups)) (not (kindIs "slice" .resources)) (eq (len .apiGroups) 0) (eq (len .resources) 0) -}}
{{- fail "extraRules must name non-empty apiGroups and resources lists" -}}
{{- end -}}
{{- if ne (toJson .verbs) "[\"list\"]" -}}
{{- fail "extraRules verbs must be exactly [list]" -}}
{{- end -}}
{{- range .apiGroups -}}
{{- if or (not (kindIs "string" .)) (not (regexMatch "^([a-z0-9]([-a-z0-9.]*[a-z0-9])?)?$" .)) -}}
{{- fail (printf "extraRules apiGroup %q is not allowed: name each API group" (toString .)) -}}
{{- end -}}
{{- end -}}
{{- $core := has "" .apiGroups -}}
{{- range .resources -}}
{{- if or (not (kindIs "string" .)) (not (regexMatch "^[a-z][a-z0-9-]*(/(status|scale))?$" .)) -}}
{{- fail (printf "extraRules resource %q is not allowed: wildcards and subresources other than status and scale reach beyond read-only configuration" (toString .)) -}}
{{- end -}}
{{- if and $core (eq (first (splitList "/" .)) "secrets") (not $root.Values.grantSecretsRead) -}}
{{- fail "extraRules core secrets require grantSecretsRead=true" -}}
{{- end -}}
{{- if and $core (eq (first (splitList "/" .)) "configmaps") (eq (toString $root.Values.grantConfigMapsRead) "false") -}}
{{- fail "extraRules core configmaps require grantConfigMapsRead=true" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
