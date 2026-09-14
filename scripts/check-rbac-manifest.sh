#!/usr/bin/env bash
# Fails when manifests/nullify-readonly-rbac.yaml differs from the default render
# of helm-charts/nullify-k8s-readonly-access. Only the labels Helm adds for its
# own bookkeeping (helm.sh/chart, app.kubernetes.io/instance and
# app.kubernetes.io/managed-by) are ignored.
#
# Requires: helm, yq (mikefarah v4), diff.
set -euo pipefail

chart="helm-charts/nullify-k8s-readonly-access"
manifest="manifests/nullify-readonly-rbac.yaml"

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
helm template nullify-k8s-readonly-access "$chart" >"$rendered"

normalise() {
  yq eval-all -o=json -P '
    [
      select(. != null and .kind != null)
      | del(.metadata.labels["helm.sh/chart"])
      | del(.metadata.labels["app.kubernetes.io/instance"])
      | del(.metadata.labels["app.kubernetes.io/managed-by"])
    ] | sort_by(.kind) | sort_keys(..)
  ' "$1"
}

if ! diff -u <(normalise "$manifest") <(normalise "$rendered"); then
  echo "::error file=$manifest::differs from the default render of $chart (diff above: - manifest, + chart)"
  exit 1
fi
echo "$manifest matches the default render of $chart"
