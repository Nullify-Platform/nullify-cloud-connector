#!/usr/bin/env bash
# Builds the complete Helm repository that GitHub Pages serves.
#
# A Pages deploy replaces the whole site, so every chart version already listed
# in the live index.yaml is downloaded again (and checked against its recorded
# digest) and republished beside any new versions. A chart whose Chart.yaml
# version is already published must package to the same contents; otherwise the
# build fails and asks for a version bump instead of silently replacing it.
#
# Usage: scripts/publish-helm-repo.sh [SITE_DIR]
#
# Environment:
#   HELM_REPO_URL        public URL of the repository (default: the Pages URL)
#   CHARTS_DIR           directory holding one chart per subdirectory (default: helm-charts)
#   PUBLISHED_LIST       file that receives "<name> <version>" for each newly packaged chart
#                        (default: published.txt)
#   HELM_REPO_BOOTSTRAP  set to "true" to allow a missing live index (first publish only)
#
# Requires: helm, yq (mikefarah v4), jq, curl, sha256sum, tar, diff.
set -euo pipefail

SITE_DIR="${1:-_site}"
REPO_URL="${HELM_REPO_URL:-https://nullify-platform.github.io/nullify-cloud-connector/}"
REPO_URL="${REPO_URL%/}/"
CHARTS_DIR="${CHARTS_DIR:-helm-charts}"
PUBLISHED_LIST="${PUBLISHED_LIST:-published.txt}"

die() {
  echo "error: $*" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$SITE_DIR"
[ -z "$(ls -A "$SITE_DIR")" ] || die "$SITE_DIR must be empty"
: >"$PUBLISHED_LIST"

old_index="$work/old-index.yaml"
status="$(curl -sSL -o "$old_index" -w '%{http_code}' "${REPO_URL}index.yaml")"
case "$status" in
  200) ;;
  404)
    [ "${HELM_REPO_BOOTSTRAP:-}" = "true" ] ||
      die "${REPO_URL}index.yaml returned 404; refusing to publish a repository without its history (set HELM_REPO_BOOTSTRAP=true for a first publish)"
    printf 'apiVersion: v1\nentries: {}\n' >"$old_index"
    ;;
  *) die "fetching ${REPO_URL}index.yaml returned HTTP $status" ;;
esac

old_json="$work/old-index.json"
yq -o=json '.' "$old_index" >"$old_json"

while IFS=$'\t' read -r name version digest url; do
  case "$url" in
    http://* | https://*) ;;
    *) url="${REPO_URL}${url}" ;;
  esac
  file="$SITE_DIR/$(basename "$url")"
  curl -fsSL -o "$file" "$url" || die "could not download published $name $version from $url"
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$actual" = "$digest" ] || die "$url has digest $actual, index records $digest"
  echo "kept $name $version"
done < <(jq -r '(.entries // {})[][] | [.name, .version, .digest, .urls[0]] | @tsv' "$old_json")

same_contents() {
  local published="$1" candidate="$2" a="$work/cmp/published" b="$work/cmp/candidate"
  rm -rf "$work/cmp"
  mkdir -p "$a" "$b"
  tar -xzf "$published" -C "$a"
  tar -xzf "$candidate" -C "$b"
  # helm package re-serialises Chart.yaml, so compare it as data, and every other file byte for byte.
  diff -r --exclude=Chart.yaml "$a" "$b" >&2 || return 1
  local chart_yaml
  while IFS= read -r chart_yaml; do
    [ -f "$b/$chart_yaml" ] || return 1
    diff <(yq -o=json 'sort_keys(..)' "$a/$chart_yaml") <(yq -o=json 'sort_keys(..)' "$b/$chart_yaml") >&2 || return 1
  done < <(cd "$a" && find . -name Chart.yaml)
}

new_dir="$work/new"
mkdir -p "$new_dir"
shopt -s nullglob
for chart_yaml in "$CHARTS_DIR"/*/Chart.yaml; do
  chart="$(dirname "$chart_yaml")"
  name="$(yq -r '.name' "$chart_yaml")"
  version="$(yq -r '.version' "$chart_yaml")"

  if [ "$(yq -r '.dependencies | length' "$chart_yaml")" != "0" ]; then
    helm dependency build "$chart"
  fi
  pkg_dir="$work/pkg/$name"
  mkdir -p "$pkg_dir"
  helm package "$chart" --destination "$pkg_dir" >/dev/null
  pkg="$pkg_dir/$name-$version.tgz"
  [ -f "$pkg" ] || die "helm package did not produce $pkg"

  published_url="$(jq -r --arg n "$name" --arg v "$version" '(.entries[$n] // [])[] | select(.version == $v) | .urls[0]' "$old_json")"
  if [ -n "$published_url" ]; then
    if ! same_contents "$SITE_DIR/$(basename "$published_url")" "$pkg"; then
      die "$name $version is already published with different contents; bump version in $chart_yaml"
    fi
    echo "unchanged $name $version"
    continue
  fi

  cp "$pkg" "$new_dir/"
  echo "$name $version" >>"$PUBLISHED_LIST"
  echo "new $name $version"
done

helm repo index "$new_dir" --url "$REPO_URL" --merge "$old_index"
for pkg in "$new_dir"/*.tgz; do
  cp "$pkg" "$SITE_DIR/"
done
cp "$new_dir/index.yaml" "$SITE_DIR/index.yaml"

while IFS= read -r url; do
  [ -f "$SITE_DIR/$(basename "$url")" ] || die "index.yaml lists $url but the site has no such file"
done < <(yq -o=json '.' "$SITE_DIR/index.yaml" | jq -r '(.entries // {})[][] | .urls[0]')

echo "site ready in $SITE_DIR:"
ls -1 "$SITE_DIR"
