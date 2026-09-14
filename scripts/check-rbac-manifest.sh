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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
helm template nullify-k8s-readonly-access "$chart" >"$work/rendered.yaml"

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

normalise "$manifest" >"$work/manifest.json"
normalise "$work/rendered.yaml" >"$work/chart.json"
for side in manifest chart; do
  count="$(jq 'length' "$work/$side.json")"
  if [ "$count" != "2" ]; then
    echo "::error::$side normalised to $count objects, expected the ClusterRole and ClusterRoleBinding"
    exit 1
  fi
done

if ! diff -u "$work/manifest.json" "$work/chart.json"; then
  echo "::error file=$manifest::differs from the default render of $chart (diff above: - manifest, + chart)"
  exit 1
fi
echo "$manifest matches the default render of $chart"
