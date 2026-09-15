#!/usr/bin/env bash
# Pre-publish hook run by scripts/publish-helm-repo.sh before this chart is
# packaged: the chart is not published or tagged unless
# manifests/nullify-readonly-rbac.yaml matches its default render, because the
# kubectl and Flux GitRepository install paths pin that manifest at the tag.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
exec scripts/check-rbac-manifest.sh
