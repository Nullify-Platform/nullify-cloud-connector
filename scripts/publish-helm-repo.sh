#!/usr/bin/env bash
# Builds the complete Helm repository that GitHub Pages serves.
#
# A Pages deploy replaces the whole site, so every chart version already listed
# in the live index.yaml is downloaded again (and checked against its recorded
# digest) and republished beside any new versions. A chart whose Chart.yaml
# version is already published must package to the same contents.
#
# The fetched index can be a stale CDN copy: GitHub Pages ignores query strings
# and no-cache request headers. So history is cross-checked against git tags
# before anything is built, and the release job creates each version's tag and
# release before it deploys. Every <chart>-v<version> tag of a chart in
# CHARTS_DIR or in the index, and each legacy collector tag in LEGACY_TAGS, must
# have its version in the fetched index. A missing version means the index is
# stale, a deploy failed after tagging, or a deploy removed it. With
# HELM_REPO_RECOVER_FROM_RELEASES=true (every job in the workflow) each missing
# version is restored from the <chart>-<version>.tgz asset on its GitHub release
# and reported as a ::warning::, so the next release on main republishes it;
# without it the build stops. A recovered asset must have the same contents as
# the chart named <chart> in CHARTS_DIR packaged from the tag, and the tag's
# commit must be on MAIN_BRANCH; a legacy version's asset must match the sha256
# pinned in LEGACY_TAGS. A version that fails either check stops the build.
#
# Charts are independent. A chart is skipped with an ::error:: annotation and
# listed in SKIPPED_LIST when it fails scripts/test-helm-charts.sh, when its
# <chart>/ci/pre-publish.sh hook exits non-zero, when its already-published
# version would change contents, or when its release already carries a
# different asset; the other charts still publish. PUBLISH_STRICT=true turns a
# skip into a failure (used by the per-chart validate job).
#
# Pre-publish hook: <chart>/ci/pre-publish.sh, if present, runs from the
# repository root as `bash <chart>/ci/pre-publish.sh <chart>` before the chart
# is packaged, whatever the calling workflow's job dependencies are.
#
# Usage: scripts/publish-helm-repo.sh [SITE_DIR]
#
# Environment:
#   HELM_REPO_URL                    public URL of the repository (default: the Pages URL)
#   CHARTS_DIR                       directory holding one chart per subdirectory (default: helm-charts)
#   PUBLISH_ONLY_CHART               build only this chart directory (e.g. helm-charts/foo); others are not packaged
#   PUBLISH_STRICT                   "true": exit non-zero instead of skipping a chart
#   PUBLISH_RUN_CHART_TESTS          "true": run scripts/test-helm-charts.sh on each chart before packaging it
#   PUBLISH_CHECK_RELEASE_ASSETS     "true": skip a chart version whose GitHub release has a different tgz asset (needs gh)
#   PUBLISHED_LIST                   receives "<name> <version>" for each newly packaged chart (default: published.txt)
#   RELEASE_LIST                     receives "<name> <version> <commit>" for every chart version at HEAD that the
#                                    site serves and that needs a <chart>-v<version> tag and release. <commit> is
#                                    HEAD for a new version, otherwise the last commit that changed the chart
#                                    directory or manifests/ (default: release.txt)
#   SKIPPED_LIST                     receives "<name> <version> <reason>" for each skipped chart (default: skipped.txt)
#   HELM_REPO_BOOTSTRAP              "true": allow a missing live index (first publish only)
#   HELM_REPO_RECOVER_FROM_RELEASES  "true": restore tagged versions missing from the index from release assets
#   TAG_REMOTE                       git remote whose tags are checked (default: origin)
#   MAIN_BRANCH                      branch a recovered tag's commit must be on (default: main)
#   GITHUB_REPOSITORY                owner/repo for releases (default: Nullify-Platform/nullify-cloud-connector)
#
# Requires: helm, yq (mikefarah v4), jq, curl, git, sha256sum, tar, diff, awk; gh when recovering or checking assets.
set -euo pipefail
shopt -s nullglob

SITE_DIR="${1:-_site}"
REPO_URL="${HELM_REPO_URL:-https://nullify-platform.github.io/nullify-cloud-connector/}"
REPO_URL="${REPO_URL%/}/"
CHARTS_DIR="${CHARTS_DIR:-helm-charts}"
PUBLISHED_LIST="${PUBLISHED_LIST:-published.txt}"
RELEASE_LIST="${RELEASE_LIST:-release.txt}"
SKIPPED_LIST="${SKIPPED_LIST:-skipped.txt}"
TAG_REMOTE="${TAG_REMOTE:-origin}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
REPOSITORY="${GITHUB_REPOSITORY:-Nullify-Platform/nullify-cloud-connector}"

# Tags from before the <chart>-v<version> scheme, as
# "<tag> <chart> <version> <sha256 of the published tgz>". v0.1.2 is
# deliberately absent: its tree holds chart version 0.2.0, and no 0.1.2 package
# survived the old replace-the-site workflow.
LEGACY_TAGS=(
  "v0.2.0 nullify-k8s-collector 0.2.0 19feed1633d8375ffae970748abdccb36c5a46c880736c17e63da8498d19d8a4"
)

die() {
  echo "error: $*" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Prints "<tag> <sha256>" when <chart> <version> is a legacy release.
legacy_entry() {
  local entry tag chart version digest
  for entry in "${LEGACY_TAGS[@]}"; do
    read -r tag chart version digest <<<"$entry"
    if [ "$chart" = "$1" ] && [ "$version" = "$2" ]; then
      echo "$tag $digest"
      return 0
    fi
  done
  return 1
}

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

mkdir -p "$SITE_DIR"
[ -z "$(ls -A "$SITE_DIR")" ] || die "$SITE_DIR must be empty"
: >"$PUBLISHED_LIST"
: >"$RELEASE_LIST"
: >"$SKIPPED_LIST"

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
  if legacy="$(legacy_entry "$name" "$version")"; then
    [ "$actual" = "${legacy#* }" ] ||
      die "$name $version has digest $actual, but legacy tag ${legacy%% *} pins ${legacy#* }"
  fi
  printf '%s\t%s\t%s\n' "$name" "$version" "$file" >>"$known"
  echo "kept $name $version"
done < <(jq -r '(.entries // {})[][] | [.name, .version, .digest, .urls[0]] | @tsv' "$old_json")

is_known() {
  awk -F'\t' -v n="$1" -v v="$2" '$1 == n && $2 == v { found = 1 } END { exit !found }' "$known"
}

known_file() {
  awk -F'\t' -v n="$1" -v v="$2" '$1 == n && $2 == v { print $3; exit }' "$known"
}

# Chart names a <chart>-v<version> tag is checked for: charts in CHARTS_DIR and
# charts in the index. Any other tag of that shape is not a chart release.
chart_names="$work/chart-names.txt"
{
  for chart_yaml in "$CHARTS_DIR"/*/Chart.yaml; do
    yq -r '.name' "$chart_yaml"
  done
  jq -r '(.entries // {}) | keys[]' "$old_json"
} | sort -u >"$chart_names"

tags="$work/tags.txt"
git ls-remote --tags --refs "$TAG_REMOTE" >"$work/ls-remote.txt" ||
  die "git ls-remote --tags $TAG_REMOTE failed; the index cannot be checked against tagged releases"
sed 's#.*refs/tags/##' "$work/ls-remote.txt" | sort -u >"$tags"

# "<tag>\t<chart>\t<version>" for every tagged release the index must contain.
tagged="$work/tagged.tsv"
: >"$tagged"
while IFS= read -r tag; do
  if [[ "$tag" =~ ^(.+)-v([0-9]+\.[0-9]+\.[0-9]+([-+].*)?)$ ]]; then
    tag_chart="${BASH_REMATCH[1]}"
    tag_version="${BASH_REMATCH[2]}"
    if grep -qxF -- "$tag_chart" "$chart_names"; then
      printf '%s\t%s\t%s\n' "$tag" "$tag_chart" "$tag_version" >>"$tagged"
    else
      echo "ignoring tag $tag: no chart named $tag_chart in $CHARTS_DIR or the index"
    fi
  fi
done <"$tags"
for entry in "${LEGACY_TAGS[@]}"; do
  read -r tag chart version _ <<<"$entry"
  if grep -qxF -- "$tag" "$tags"; then
    printf '%s\t%s\t%s\n' "$tag" "$chart" "$version" >>"$tagged"
  fi
done

# Prints the CHARTS_DIR subdirectory whose Chart.yaml at <commit> is chart <name>.
chart_dir_at() {
  local commit="$1" name="$2" dir
  while IFS= read -r dir; do
    if git cat-file -e "$commit:$dir/Chart.yaml" 2>/dev/null &&
      [ "$(git show "$commit:$dir/Chart.yaml" | yq -r '.name')" = "$name" ]; then
      echo "$dir"
      return 0
    fi
  done < <(git ls-tree -d --name-only "$commit" "$CHARTS_DIR/")
  return 1
}

# Requires <tag> to be on MAIN_BRANCH and the chart named <name> in CHARTS_DIR,
# packaged from the tag's tree, to have the same contents as <asset>.
verify_against_tag_tree() {
  local tag="$1" name="$2" version="$3" asset="$4"
  local chart src="$work/recover-src/$tag"
  if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch -q --unshallow "$TAG_REMOTE" </dev/null || die "could not unshallow the checkout to verify tag $tag"
  fi
  git fetch -q --no-tags "$TAG_REMOTE" \
    "+refs/heads/$MAIN_BRANCH:refs/remotes/$TAG_REMOTE/$MAIN_BRANCH" \
    "+refs/tags/$tag:refs/tags/$tag" </dev/null ||
    die "could not fetch $MAIN_BRANCH and tag $tag from $TAG_REMOTE to verify $(basename "$asset")"
  git merge-base --is-ancestor "refs/tags/$tag^{commit}" "refs/remotes/$TAG_REMOTE/$MAIN_BRANCH" ||
    die "tag $tag is not on $MAIN_BRANCH; refusing to recover $name $version from it"
  chart="$(chart_dir_at "refs/tags/$tag^{commit}" "$name")" ||
    die "tag $tag has no $CHARTS_DIR/*/Chart.yaml with name $name; refusing to recover $name $version from it"
  mkdir -p "$src/pkg"
  git archive "refs/tags/$tag^{commit}" "$chart" | tar -x -C "$src" ||
    die "could not extract $chart from tag $tag"
  [ "$(yq -r '.name' "$src/$chart/Chart.yaml")" = "$name" ] || die "$chart/Chart.yaml at tag $tag is not chart $name"
  [ "$(yq -r '.version' "$src/$chart/Chart.yaml")" = "$version" ] || die "$chart/Chart.yaml at tag $tag is not version $version"
  if [ "$(yq -r '.dependencies | length' "$src/$chart/Chart.yaml")" != "0" ]; then
    helm dependency build "$src/$chart" >&2
  fi
  helm package "$src/$chart" --destination "$src/pkg" >/dev/null
  [ -f "$src/pkg/$name-$version.tgz" ] || die "helm package of $chart at tag $tag did not produce $name-$version.tgz"
  same_contents "$asset" "$src/pkg/$name-$version.tgz" ||
    die "release asset $(basename "$asset") differs from $chart packaged at tag $tag (diff above); refusing to recover it"
}

recover_from_release() {
  local tag="$1" name="$2" version="$3"
  local asset="$name-$version.tgz" dir="$work/recover/$tag"
  mkdir -p "$dir"
  gh release download "$tag" -R "$REPOSITORY" -p "$asset" -D "$dir" </dev/null ||
    die "release $tag has no asset $asset to recover $name $version from"
  local recorded actual chart_yaml legacy
  recorded="$(gh release view "$tag" -R "$REPOSITORY" --json assets \
    --jq ".assets[] | select(.name == \"$asset\") | .digest" </dev/null | sed 's/^sha256://')"
  actual="$(sha256sum "$dir/$asset" | cut -d' ' -f1)"
  [ -n "$recorded" ] || die "release $tag records no digest for $asset; restore it by hand"
  [ "$actual" = "$recorded" ] || die "release asset $asset has digest $actual, release $tag records $recorded"
  chart_yaml="$(tar -xzOf "$dir/$asset" "$name/Chart.yaml")" || die "$asset has no $name/Chart.yaml"
  [ "$(yq -r '.name' <<<"$chart_yaml")" = "$name" ] || die "$asset from $tag is not chart $name"
  [ "$(yq -r '.version' <<<"$chart_yaml")" = "$version" ] || die "$asset from $tag is not version $version"
  if legacy="$(legacy_entry "$name" "$version")"; then
    [ "$actual" = "${legacy#* }" ] ||
      die "release asset $asset has digest $actual, but $name $version is pinned to ${legacy#* }"
  else
    verify_against_tag_tree "$tag" "$name" "$version" "$dir/$asset"
  fi
  cp "$dir/$asset" "$SITE_DIR/$asset"
  printf '%s\t%s\t%s\n' "$name" "$version" "$SITE_DIR/$asset" >>"$known"
  echo "recovered $name $version from release $tag (sha256 $actual)"
  echo "::warning::$name $version is tagged ($tag) but missing from ${REPO_URL}index.yaml; restored from its verified release asset, and the next release on $MAIN_BRANCH republishes it"
}

# Prints the path of release <name>-v<version>'s <name>-<version>.tgz asset,
# downloaded and checked against its recorded digest, or nothing when the release
# has no such asset. Fails when the asset cannot be downloaded or verified.
fetch_release_asset() {
  local name="$1" version="$2" tag="$1-v$2" asset="$1-$2.tgz" recorded dir
  recorded="$(awk -F'\t' -v t="$tag" -v a="$asset" '$1 == t && $2 == a { print $3; exit }' "$release_assets")"
  [ -n "$recorded" ] || return 0
  [ "$recorded" != "none" ] || return 1
  dir="$work/release-asset/$tag"
  mkdir -p "$dir"
  gh release download "$tag" -R "$REPOSITORY" -p "$asset" -D "$dir" --clobber </dev/null >&2 || return 1
  [ "$recorded" = "sha256:$(sha256sum "$dir/$asset" | cut -d' ' -f1)" ] || return 1
  echo "$dir/$asset"
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
is a stale CDN copy, a deploy failed after its tags and releases were created,
or a deploy removed them. Set HELM_REPO_RECOVER_FROM_RELEASES=true (the "Helm
charts" workflow always does) to restore them from their verified GitHub release
assets. A tag that is not a real chart release has to be deleted instead.
EOF
  exit 1
fi

# "<tag>\t<asset>\t<digest>" for every asset on every release.
release_assets="$work/release-assets.tsv"
: >"$release_assets"
if [ "${PUBLISH_CHECK_RELEASE_ASSETS:-}" = "true" ]; then
  gh api --paginate "repos/$REPOSITORY/releases" \
    --jq '.[] | .tag_name as $tag | .assets[] | [$tag, .name, (.digest // "none")] | @tsv' \
    </dev/null >"$release_assets" ||
    die "listing the releases of $REPOSITORY failed; release assets cannot be checked"
fi

# Fails when release <name>-v<version> already has a <name>-<version>.tgz asset
# whose digest is not that of <file>.
release_asset_matches() {
  local name="$1" version="$2" file="$3" recorded
  recorded="$(awk -F'\t' -v t="$name-v$version" -v a="$name-$version.tgz" \
    '$1 == t && $2 == a { print $3; exit }' "$release_assets")"
  [ -z "$recorded" ] || [ "$recorded" = "sha256:$(sha256sum "$file" | cut -d' ' -f1)" ]
}

skip_chart() {
  local name="$1" version="$2" chart_yaml="$3" reason="$4"
  echo "::error file=$chart_yaml::$name $version skipped: $reason"
  printf '%s %s %s\n' "$name" "$version" "$reason" >>"$SKIPPED_LIST"
  [ "${PUBLISH_STRICT:-}" != "true" ] || die "$name $version: $reason"
}

queue_release() {
  local name="$1" version="$2" commit="$3"
  if legacy_entry "$name" "$version" >/dev/null; then
    return 0
  fi
  echo "$name $version $commit" >>"$RELEASE_LIST"
}

charts=("$CHARTS_DIR"/*/Chart.yaml)
if [ -n "${PUBLISH_ONLY_CHART:-}" ]; then
  [ -f "${PUBLISH_ONLY_CHART%/}/Chart.yaml" ] || die "PUBLISH_ONLY_CHART=$PUBLISH_ONLY_CHART has no Chart.yaml"
  charts=("${PUBLISH_ONLY_CHART%/}/Chart.yaml")
fi

head_commit="$(git rev-parse HEAD)"

for chart_yaml in "${charts[@]}"; do
  chart="$(dirname "$chart_yaml")"
  name="$(yq -r '.name' "$chart_yaml")"
  version="$(yq -r '.version' "$chart_yaml")"

  if [ "${PUBLISH_RUN_CHART_TESTS:-}" = "true" ] && ! scripts/test-helm-charts.sh "$chart"; then
    skip_chart "$name" "$version" "$chart_yaml" "scripts/test-helm-charts.sh $chart failed"
    continue
  fi

  hook="$chart/ci/pre-publish.sh"
  if [ -f "$hook" ] && ! bash "$hook" "$chart"; then
    skip_chart "$name" "$version" "$chart_yaml" "$hook failed"
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
    published="$(known_file "$name" "$version")"
    if ! same_contents "$published" "$pkg"; then
      skip_chart "$name" "$version" "$chart_yaml" "already published with different contents; bump version in $chart_yaml"
      continue
    fi
    if ! release_asset_matches "$name" "$version" "$published"; then
      skip_chart "$name" "$version" "$chart_yaml" "release $name-v$version has a $name-$version.tgz asset that differs from the published package"
      continue
    fi
    last_change="$(git log -1 --format=%H -- "$chart" manifests/)"
    queue_release "$name" "$version" "${last_change:-$head_commit}"
    echo "unchanged $name $version"
    continue
  fi

  # helm package output is not byte-reproducible, so an existing asset is
  # compared by contents and, when they match, published in place of $pkg so the
  # site serves the bytes the release already carries.
  if ! existing="$(fetch_release_asset "$name" "$version")"; then
    skip_chart "$name" "$version" "$chart_yaml" "release $name-v$version has a $name-$version.tgz asset that could not be downloaded or does not match its recorded digest"
    continue
  fi
  if [ -n "$existing" ]; then
    if ! same_contents "$existing" "$pkg"; then
      skip_chart "$name" "$version" "$chart_yaml" "release $name-v$version already has a $name-$version.tgz asset with other contents; delete that release or bump version in $chart_yaml"
      continue
    fi
    pkg="$existing"
  fi
  cp "$pkg" "$new_dir/"
  echo "$name $version" >>"$PUBLISHED_LIST"
  queue_release "$name" "$version" "$head_commit"
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
