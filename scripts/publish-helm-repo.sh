#!/usr/bin/env bash
# Builds the complete Helm repository that GitHub Pages serves.
#
# A Pages deploy replaces the whole site, so every chart version already listed
# in the live index.yaml is downloaded again (and checked against its recorded
# digest) and republished beside any new versions. A chart whose Chart.yaml
# version is already published must package to the same contents.
#
# History is cross-checked against git tags before anything is built: every
# <chart>-v<version> tag, and each legacy collector tag in LEGACY_TAGS, must
# have its version in the fetched index. A missing version means the index is
# stale or a release wiped it, and the build stops. Set
# HELM_REPO_RECOVER_FROM_RELEASES=true to restore each missing version from the
# <chart>-<version>.tgz asset on its GitHub release instead (digest-checked
# against the asset's recorded sha256).
#
# Charts are independent. A chart that fails scripts/test-helm-charts.sh, or
# whose already-published version would change contents, is skipped with an
# ::error:: annotation and listed in SKIPPED_LIST; the other charts still
# publish. PUBLISH_STRICT=true turns a skip into a failure (used by the
# per-chart validate job).
#
# Usage: scripts/publish-helm-repo.sh [SITE_DIR]
#
# Environment:
#   HELM_REPO_URL                    public URL of the repository (default: the Pages URL)
#   CHARTS_DIR                       directory holding one chart per subdirectory (default: helm-charts)
#   PUBLISH_ONLY_CHART               build only this chart directory (e.g. helm-charts/foo); others are not packaged
#   PUBLISH_STRICT                   "true": exit non-zero instead of skipping a chart
#   PUBLISH_RUN_CHART_TESTS          "true": run scripts/test-helm-charts.sh on each chart before packaging it
#   PUBLISHED_LIST                   receives "<name> <version>" for each newly packaged chart (default: published.txt)
#   RELEASE_LIST                     receives "<name> <version>" for every chart version at HEAD that the site
#                                    serves and that needs a <chart>-v<version> tag and release (default: release.txt)
#   SKIPPED_LIST                     receives "<name> <version> <reason>" for each skipped chart (default: skipped.txt)
#   HELM_REPO_BOOTSTRAP              "true": allow a missing live index (first publish only)
#   HELM_REPO_RECOVER_FROM_RELEASES  "true": restore tagged versions missing from the index from release assets
#   TAG_REMOTE                       git remote whose tags are checked (default: origin)
#   GITHUB_REPOSITORY                owner/repo for release downloads (default: Nullify-Platform/nullify-cloud-connector)
#   GITHUB_RUN_ID                    cache-busting value for the index fetch (default: current time)
#
# Requires: helm, yq (mikefarah v4), jq, curl, git, sha256sum, tar, diff; gh when recovering.
set -euo pipefail

SITE_DIR="${1:-_site}"
REPO_URL="${HELM_REPO_URL:-https://nullify-platform.github.io/nullify-cloud-connector/}"
REPO_URL="${REPO_URL%/}/"
CHARTS_DIR="${CHARTS_DIR:-helm-charts}"
PUBLISHED_LIST="${PUBLISHED_LIST:-published.txt}"
RELEASE_LIST="${RELEASE_LIST:-release.txt}"
SKIPPED_LIST="${SKIPPED_LIST:-skipped.txt}"
TAG_REMOTE="${TAG_REMOTE:-origin}"
REPOSITORY="${GITHUB_REPOSITORY:-Nullify-Platform/nullify-cloud-connector}"

# Tags from before the <chart>-v<version> scheme, as "<tag> <chart> <version>".
# v0.1.2 is deliberately absent: its tree holds chart version 0.2.0, and no
# 0.1.2 package survived the old replace-the-site workflow.
LEGACY_TAGS=(
  "v0.2.0 nullify-k8s-collector 0.2.0"
)

die() {
  echo "error: $*" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$SITE_DIR"
[ -z "$(ls -A "$SITE_DIR")" ] || die "$SITE_DIR must be empty"
: >"$PUBLISHED_LIST"
: >"$RELEASE_LIST"
: >"$SKIPPED_LIST"

old_index="$work/old-index.yaml"
status="$(curl -sSL -o "$old_index" -w '%{http_code}' \
  -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
  "${REPO_URL}index.yaml?run=${GITHUB_RUN_ID:-$(date +%s)}")"
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

# "<name>\t<version>\t<file in SITE_DIR>" for every version the site will serve
# before new packages are added.
known="$work/known.tsv"
: >"$known"

while IFS=$'\t' read -r name version digest url; do
  case "$url" in
    http://* | https://*) ;;
    *) url="${REPO_URL}${url}" ;;
  esac
  file="$SITE_DIR/$(basename "$url")"
  curl -fsSL -o "$file" "$url" || die "could not download published $name $version from $url"
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$actual" = "$digest" ] || die "$url has digest $actual, index records $digest"
  printf '%s\t%s\t%s\n' "$name" "$version" "$file" >>"$known"
  echo "kept $name $version"
done < <(jq -r '(.entries // {})[][] | [.name, .version, .digest, .urls[0]] | @tsv' "$old_json")

is_known() {
  awk -F'\t' -v n="$1" -v v="$2" '$1 == n && $2 == v { found = 1 } END { exit !found }' "$known"
}

known_file() {
  awk -F'\t' -v n="$1" -v v="$2" '$1 == n && $2 == v { print $3; exit }' "$known"
}

legacy_tag_for() {
  local entry tag chart version
  for entry in "${LEGACY_TAGS[@]}"; do
    read -r tag chart version <<<"$entry"
    if [ "$chart" = "$1" ] && [ "$version" = "$2" ]; then
      echo "$tag"
      return 0
    fi
  done
  return 1
}

tags="$work/tags.txt"
git ls-remote --tags --refs "$TAG_REMOTE" >"$work/ls-remote.txt" ||
  die "git ls-remote --tags $TAG_REMOTE failed; the index cannot be checked against tagged releases"
sed 's#.*refs/tags/##' "$work/ls-remote.txt" | sort -u >"$tags"

# "<tag>\t<chart>\t<version>" for every tagged release the index must contain.
tagged="$work/tagged.tsv"
: >"$tagged"
while IFS= read -r tag; do
  if [[ "$tag" =~ ^(.+)-v([0-9]+\.[0-9]+\.[0-9]+([-+].*)?)$ ]]; then
    printf '%s\t%s\t%s\n' "$tag" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >>"$tagged"
  fi
done <"$tags"
for entry in "${LEGACY_TAGS[@]}"; do
  read -r tag chart version <<<"$entry"
  if grep -qxF -- "$tag" "$tags"; then
    printf '%s\t%s\t%s\n' "$tag" "$chart" "$version" >>"$tagged"
  fi
done

recover_from_release() {
  local tag="$1" name="$2" version="$3"
  local asset="$name-$version.tgz" dir="$work/recover/$tag"
  mkdir -p "$dir"
  gh release download "$tag" -R "$REPOSITORY" -p "$asset" -D "$dir" </dev/null ||
    die "release $tag has no asset $asset to recover $name $version from"
  local recorded actual chart_yaml
  recorded="$(gh release view "$tag" -R "$REPOSITORY" --json assets \
    --jq ".assets[] | select(.name == \"$asset\") | .digest" </dev/null | sed 's/^sha256://')"
  actual="$(sha256sum "$dir/$asset" | cut -d' ' -f1)"
  [ -n "$recorded" ] || die "release $tag records no digest for $asset; restore it by hand"
  [ "$actual" = "$recorded" ] || die "release asset $asset has digest $actual, release $tag records $recorded"
  chart_yaml="$(tar -xzOf "$dir/$asset" "$name/Chart.yaml")" || die "$asset has no $name/Chart.yaml"
  [ "$(yq -r '.name' <<<"$chart_yaml")" = "$name" ] || die "$asset from $tag is not chart $name"
  [ "$(yq -r '.version' <<<"$chart_yaml")" = "$version" ] || die "$asset from $tag is not version $version"
  cp "$dir/$asset" "$SITE_DIR/$asset"
  printf '%s\t%s\t%s\n' "$name" "$version" "$SITE_DIR/$asset" >>"$known"
  echo "recovered $name $version from release $tag (sha256 $actual)"
}

new_dir="$work/new"
mkdir -p "$new_dir"

missing=()
while IFS=$'\t' read -r tag name version; do
  is_known "$name" "$version" && continue
  if [ "${HELM_REPO_RECOVER_FROM_RELEASES:-}" = "true" ]; then
    recover_from_release "$tag" "$name" "$version"
    cp "$SITE_DIR/$name-$version.tgz" "$new_dir/"
  else
    missing+=("$name $version (tag $tag)")
  fi
done <"$tagged"
if [ ${#missing[@]} -gt 0 ]; then
  printf 'error: tagged chart versions missing from %sindex.yaml:\n' "$REPO_URL" >&2
  printf '  %s\n' "${missing[@]}" >&2
  cat >&2 <<EOF
Refusing to build: deploying now would unpublish them. Either the fetched index
is a stale cached copy (re-run in a few minutes), or a deploy removed them.
To restore them from their GitHub release assets, re-run the "Helm charts"
workflow on main with recover_from_releases=true
(HELM_REPO_RECOVER_FROM_RELEASES=true locally).
EOF
  exit 1
fi

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

skip_chart() {
  local name="$1" version="$2" chart_yaml="$3" reason="$4"
  echo "::error file=$chart_yaml::$name $version skipped: $reason"
  printf '%s %s %s\n' "$name" "$version" "$reason" >>"$SKIPPED_LIST"
  [ "${PUBLISH_STRICT:-}" != "true" ] || die "$name $version: $reason"
}

queue_release() {
  local name="$1" version="$2"
  if legacy_tag_for "$name" "$version" >/dev/null; then
    return 0
  fi
  echo "$name $version" >>"$RELEASE_LIST"
}

shopt -s nullglob
charts=("$CHARTS_DIR"/*/Chart.yaml)
if [ -n "${PUBLISH_ONLY_CHART:-}" ]; then
  [ -f "${PUBLISH_ONLY_CHART%/}/Chart.yaml" ] || die "PUBLISH_ONLY_CHART=$PUBLISH_ONLY_CHART has no Chart.yaml"
  charts=("${PUBLISH_ONLY_CHART%/}/Chart.yaml")
fi

for chart_yaml in "${charts[@]}"; do
  chart="$(dirname "$chart_yaml")"
  name="$(yq -r '.name' "$chart_yaml")"
  version="$(yq -r '.version' "$chart_yaml")"

  if [ "${PUBLISH_RUN_CHART_TESTS:-}" = "true" ] && ! scripts/test-helm-charts.sh "$chart"; then
    skip_chart "$name" "$version" "$chart_yaml" "scripts/test-helm-charts.sh $chart failed"
    continue
  fi

  if [ "$(yq -r '.dependencies | length' "$chart_yaml")" != "0" ]; then
    helm dependency build "$chart"
  fi
  pkg_dir="$work/pkg/$name"
  mkdir -p "$pkg_dir"
  helm package "$chart" --destination "$pkg_dir" >/dev/null
  pkg="$pkg_dir/$name-$version.tgz"
  [ -f "$pkg" ] || die "helm package did not produce $pkg"

  if is_known "$name" "$version"; then
    if ! same_contents "$(known_file "$name" "$version")" "$pkg"; then
      skip_chart "$name" "$version" "$chart_yaml" "already published with different contents; bump version in $chart_yaml"
      continue
    fi
    queue_release "$name" "$version"
    echo "unchanged $name $version"
    continue
  fi

  cp "$pkg" "$new_dir/"
  echo "$name $version" >>"$PUBLISHED_LIST"
  queue_release "$name" "$version"
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

while IFS=$'\t' read -r tag name version; do
  yq -o=json '.' "$SITE_DIR/index.yaml" |
    jq -e --arg n "$name" --arg v "$version" '(.entries[$n] // [])[] | select(.version == $v)' >/dev/null ||
    die "built index.yaml lacks tagged $name $version (tag $tag)"
done <"$tagged"

echo "site ready in $SITE_DIR:"
ls -1 "$SITE_DIR"
if [ -s "$SKIPPED_LIST" ]; then
  echo "skipped charts (not published):"
  cat "$SKIPPED_LIST"
fi
