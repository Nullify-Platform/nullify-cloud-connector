#!/usr/bin/env bash
# Lints and renders one chart.
#
# - With every values file in <chart>/ci/*.yaml, or with the chart defaults when
#   the chart has none.
# - Every values file in tests/helm/<chart-dir>/must-fail/*.yaml must be rejected
#   at render time with the message given on its "# expect: <text>" line.
#
# Usage: scripts/test-helm-charts.sh helm-charts/<chart>
set -euo pipefail

chart="${1:?usage: $0 helm-charts/<chart>}"
chart="${chart%/}"
name="$(basename "$chart")"
shopt -s nullglob

err="$(mktemp)"
trap 'rm -f "$err"' EXIT

values=("$chart"/ci/*.yaml)
if [ ${#values[@]} -eq 0 ]; then
  echo "::group::$name (default values)"
  helm lint "$chart"
  helm template "$name" "$chart" >/dev/null
  echo "::endgroup::"
else
  for v in "${values[@]}"; do
    echo "::group::$name -f $v"
    helm lint "$chart" -f "$v"
    helm template "$name" "$chart" -f "$v" >/dev/null
    echo "::endgroup::"
  done
fi

for v in "tests/helm/$name/must-fail"/*.yaml; do
  expect="$(sed -n 's/^# expect: //p' "$v" | head -n 1)"
  if [ -z "$expect" ]; then
    echo "::error file=$v::missing '# expect: <text>' line"
    exit 1
  fi
  if helm template "$name" "$chart" -f "$v" >/dev/null 2>"$err"; then
    echo "::error file=$v::rendered, but these values must be rejected"
    exit 1
  fi
  if ! grep -qF -- "$expect" "$err"; then
    echo "::error file=$v::rejected, but not with '$expect'"
    cat "$err"
    exit 1
  fi
  echo "rejected as expected: $v"
done
