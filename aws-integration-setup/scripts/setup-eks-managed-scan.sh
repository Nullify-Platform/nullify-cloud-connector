#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# Nullify Cloud Connector - managed EKS scan setup (no in-cluster agent).
#
# Lets Nullify's read-only integration role list Kubernetes resources in one
# EKS cluster through the cluster's public API endpoint:
#   1. an authentication mode that supports access entries
#   2. an EKS access entry for the role
#   3. Kubernetes RBAC for group nullify-readonly, or AmazonEKSAdminViewPolicy
#   4. Nullify's egress IPs merged into publicAccessCidrs
#
# The script never assumes the Nullify role. Run with --help for usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/cidr-merge.sh
source "$SCRIPT_DIR/lib/cidr-merge.sh"

readonly MANAGED_BY_TAG_KEY="ManagedBy"
readonly MANAGED_BY_TAG_VALUE="nullify-connector"
readonly ADDED_CIDRS_TAG_KEY="nullify-added-cidrs"
readonly PENDING_CIDRS_TAG_KEY="nullify-pending-cidrs"
readonly EKS_TAG_VALUE_MAX_LENGTH=256
readonly EKS_MAX_TAGS_PER_RESOURCE=50
readonly DEFAULT_GROUP="nullify-readonly"
readonly RBAC_CLUSTER_ROLE="nullify-readonly"
readonly RBAC_MANIFEST_RELEASE_TAG="nullify-k8s-readonly-access-v0.1.0"
readonly RBAC_MANIFEST_RELEASE_URL="https://raw.githubusercontent.com/Nullify-Platform/nullify-cloud-connector/${RBAC_MANIFEST_RELEASE_TAG}/manifests/nullify-readonly-rbac.yaml"
readonly ADMIN_VIEW_WARNING="AmazonEKSAdminViewPolicy grants get, list and watch on every resource, including Secrets, custom resources and pods/log, and on EKS 1.34 and earlier get pods/exec is enough to exec into pods. Its grants do not show in kubectl auth can-i --list."
readonly VERIFY_USER="nullify-verify"
readonly UPDATE_POLL_SECONDS=15
readonly UPDATE_POLL_ATTEMPTS=80

RBAC_RESOURCES=(
  nodes namespaces pods services persistentvolumeclaims persistentvolumes
  configmaps secrets resourcequotas limitranges serviceaccounts
  deployments.apps daemonsets.apps statefulsets.apps replicasets.apps
  ingresses.networking.k8s.io networkpolicies.networking.k8s.io
  endpointslices.discovery.k8s.io
  roles.rbac.authorization.k8s.io rolebindings.rbac.authorization.k8s.io
  clusterroles.rbac.authorization.k8s.io clusterrolebindings.rbac.authorization.k8s.io
  validatingwebhookconfigurations.admissionregistration.k8s.io
  mutatingwebhookconfigurations.admissionregistration.k8s.io
  validatingadmissionpolicies.admissionregistration.k8s.io
  validatingadmissionpolicybindings.admissionregistration.k8s.io
)

ACTION=""
CLUSTER=""
REGION=""
CUSTOMER_NAME=""
ROLE_ARN=""
NULLIFY_REGION=""
AUTHORIZATION="rbac"
GROUP="$DEFAULT_GROUP"
ALLOW_AUTH_MODE_CHANGE=false
KUBE_CONTEXT=""
RBAC_MANIFEST=""
SKIP_ACCESS_ENTRY=false
SKIP_RBAC=false
SKIP_NETWORK=false
DRY_RUN=false

CLUSTER_ARN=""
ADMIN_VIEW_POLICY_ARN=""
NULLIFY_CIDRS=""
ADDED_CIDRS=""
ADDED_TAG_KEYS=""
PENDING_CIDRS=""
PENDING_TAG_KEYS=""
STORED_TAG_KEYS=""
KUBECONFIG_TMP=""
RBAC_MANIFEST_TMP_DIR=""
KUBECTL=()
VERIFY_FAILURES=0

log() { printf '%s\n' "$*" >&2; }
info() { log "[INFO] $*"; }
warn() { log "[WARN] $*"; }
die() {
  log "[ERROR] $*"
  exit 1
}

cleanup_tmp() {
  if [[ -n "$KUBECONFIG_TMP" ]]; then
    rm -f "$KUBECONFIG_TMP"
  fi
  if [[ -n "$RBAC_MANIFEST_TMP_DIR" ]]; then
    rm -rf "$RBAC_MANIFEST_TMP_DIR"
  fi
}

usage() {
  local name
  name="$(basename "$0")"
  cat <<EOF
Usage: ${name} <plan|apply|verify|remove> [options]

Give Nullify's managed EKS scan read-only access to one cluster.

Actions:
  plan     Print every change apply would make and make none. Read-only
           describe calls still run so the printed commands are concrete.
  apply    Make the changes: authentication mode (only with
           --allow-auth-mode-change), access entry, RBAC, publicAccessCidrs.
  verify   Check the access entry, RBAC (kubectl auth can-i) and publicAccessCidrs.
  remove   Undo apply: RBAC manifest objects (except Helm-managed ones), access
           entries tagged ${MANAGED_BY_TAG_KEY}=${MANAGED_BY_TAG_VALUE}, and the CIDRs
           recorded in the ${ADDED_CIDRS_TAG_KEY} cluster tag, plus any CIDRs in
           ${PENDING_CIDRS_TAG_KEY} that publicAccessCidrs includes. A public
           endpoint disabled since apply is left alone and both tags are kept, so
           remove can still take the CIDRs out after the endpoint is re-enabled.

CIDR records: apply writes ${PENDING_CIDRS_TAG_KEY} before update-cluster-config
and moves those CIDRs to ${ADDED_CIDRS_TAG_KEY} once the update succeeds. If a run
stops in between (timeout, Ctrl-C, expired credentials), re-running apply or
remove reconciles ${PENDING_CIDRS_TAG_KEY} against publicAccessCidrs, and refuses
while an EndpointAccessUpdate of the cluster is still InProgress. The records use
up to two cluster tags at once; apply stops before changing publicAccessCidrs
when the cluster is too close to EKS's limit of ${EKS_MAX_TAGS_PER_RESOURCE} tags.

Required:
  --cluster NAME             EKS cluster name
  --region REGION            Cluster region
  --customer-name NAME       CustomerName of the Nullify CloudFormation stack; the
                             role is AWSIntegration-<NAME>-NullifyReadOnlyRole in
                             the caller's account
    or --role-arn ARN        Nullify read-only role ARN
  --nullify-region REGION    Nullify region serving your tenant, which selects the
                             egress IPs: ap-southeast-2, eu-central-1 or us-east-2.
                             Not needed for remove or with --skip-network.

Options:
  --authorization MODE       rbac (default): the access entry carries --group, bound
                             by manifests/nullify-readonly-rbac.yaml.
                             admin-view: associate AmazonEKSAdminViewPolicy instead.
                             WARNING: ${ADMIN_VIEW_WARNING}
  --group NAME               Kubernetes group for rbac mode (default: ${DEFAULT_GROUP})
  --allow-auth-mode-change   Switch a CONFIG_MAP cluster to API_AND_CONFIG_MAP.
                             This is one-way: EKS cannot switch back.
  --kube-context NAME        Use this kubeconfig context instead of a temporary
                             kubeconfig written by aws eks update-kubeconfig
  --rbac-manifest PATH|URL   RBAC manifest (default: manifests/nullify-readonly-rbac.yaml
                             in this checkout, or that file at release tag
                             ${RBAC_MANIFEST_RELEASE_TAG} when the checkout lacks it;
                             the run stops if that tag is not published). Pin URLs
                             to a commit SHA or a release tag.
  --skip-access-entry        The access entry is owned by the CloudFormation stack
                             nullify-eks-managed-scan-access.json
  --skip-rbac                RBAC is applied elsewhere (Helm chart
                             nullify-k8s-readonly-access, GitOps)
  --skip-network             Do not read or change publicAccessCidrs
  --dry-run                  With apply or remove: print the changes, make none
  -h, --help                 Show this help

Examples:
  ${name} plan   --cluster prod --region eu-west-1 --customer-name acme --nullify-region eu-central-1
  ${name} apply  --cluster prod --region eu-west-1 --customer-name acme --nullify-region eu-central-1
  ${name} verify --cluster prod --region eu-west-1 --customer-name acme --nullify-region eu-central-1
  ${name} remove --cluster prod --region eu-west-1 --customer-name acme
EOF
}

need_value() {
  if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
    die "$1 needs a value"
  fi
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi
  case "$1" in
    plan | apply | verify | remove)
      ACTION="$1"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown action '$1'"
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cluster) need_value "$@"; CLUSTER="$2"; shift 2 ;;
      --region) need_value "$@"; REGION="$2"; shift 2 ;;
      --customer-name) need_value "$@"; CUSTOMER_NAME="$2"; shift 2 ;;
      --role-arn) need_value "$@"; ROLE_ARN="$2"; shift 2 ;;
      --nullify-region) need_value "$@"; NULLIFY_REGION="$2"; shift 2 ;;
      --authorization) need_value "$@"; AUTHORIZATION="$2"; shift 2 ;;
      --group) need_value "$@"; GROUP="$2"; shift 2 ;;
      --kube-context) need_value "$@"; KUBE_CONTEXT="$2"; shift 2 ;;
      --rbac-manifest) need_value "$@"; RBAC_MANIFEST="$2"; shift 2 ;;
      --allow-auth-mode-change) ALLOW_AUTH_MODE_CHANGE=true; shift ;;
      --skip-access-entry) SKIP_ACCESS_ENTRY=true; shift ;;
      --skip-rbac) SKIP_RBAC=true; shift ;;
      --skip-network) SKIP_NETWORK=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option '$1' (see --help)" ;;
    esac
  done

  if [[ "$ACTION" == plan ]]; then
    DRY_RUN=true
  fi

  if [[ -z "$CLUSTER" ]]; then
    die "--cluster is required"
  fi
  if [[ ! "$CLUSTER" =~ ^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$ ]]; then
    die "invalid cluster name '$CLUSTER'"
  fi
  if [[ -z "$REGION" ]]; then
    die "--region is required"
  fi
  if [[ ! "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]]; then
    die "invalid region '$REGION'"
  fi
  if [[ -n "$CUSTOMER_NAME" && -n "$ROLE_ARN" ]]; then
    die "pass --customer-name or --role-arn, not both"
  fi
  if [[ -z "$CUSTOMER_NAME" && -z "$ROLE_ARN" ]]; then
    die "--customer-name or --role-arn is required"
  fi
  if [[ -n "$CUSTOMER_NAME" && ! "$CUSTOMER_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,9}$ ]]; then
    die "invalid --customer-name '$CUSTOMER_NAME' (must match the CloudFormation CustomerName: letter first, max 10 characters)"
  fi
  if [[ -n "$ROLE_ARN" && ! "$ROLE_ARN" =~ ^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$ ]]; then
    die "invalid --role-arn '$ROLE_ARN'"
  fi
  case "$AUTHORIZATION" in
    rbac | admin-view) ;;
    *) die "--authorization must be rbac or admin-view" ;;
  esac
  if [[ ! "$GROUP" =~ ^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$ ]]; then
    die "invalid --group '$GROUP' (lowercase letters, digits, '.' and '-'; system: groups are not allowed)"
  fi
  if [[ "$ACTION" != remove && "$SKIP_NETWORK" != true ]]; then
    if [[ -z "$NULLIFY_REGION" ]]; then
      die "--nullify-region is required (or pass --skip-network)"
    fi
    NULLIFY_CIDRS="$(nullify_egress_cidrs "$NULLIFY_REGION")" || die "cannot select Nullify egress IPs"
  fi
}

# mutate runs a command that changes AWS or Kubernetes state, or only prints it
# under plan / --dry-run. The command line goes to stderr so callers can capture
# its stdout.
mutate() {
  local rendered
  printf -v rendered '%q ' "$@"
  if [[ "$DRY_RUN" == true ]]; then
    log "[would run] ${rendered% }"
    return 0
  fi
  log "[run] ${rendered% }"
  "$@"
}

cluster_query() {
  aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query "cluster.$1" --output text
}

resolve_role_arn() {
  local caller_arn account partition
  if [[ -z "$ROLE_ARN" ]]; then
    caller_arn="$(aws sts get-caller-identity --query Arn --output text)"
    account="$(aws sts get-caller-identity --query Account --output text)"
    partition="${caller_arn#arn:}"
    partition="${partition%%:*}"
    ROLE_ARN="arn:${partition}:iam::${account}:role/AWSIntegration-${CUSTOMER_NAME}-NullifyReadOnlyRole"
  fi
  partition="${ROLE_ARN#arn:}"
  partition="${partition%%:*}"
  ADMIN_VIEW_POLICY_ARN="arn:${partition}:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
}

preflight() {
  local status
  if ! command -v aws >/dev/null 2>&1; then
    die "the AWS CLI v2 is required"
  fi
  resolve_role_arn
  CLUSTER_ARN="$(cluster_query arn)"
  status="$(cluster_query status)"
  info "cluster: $CLUSTER_ARN (status $status)"
  info "principal: $ROLE_ARN"
  if [[ "$ACTION" != verify && "$status" != ACTIVE ]]; then
    die "cluster status is $status; wait until it is ACTIVE"
  fi
}

wait_for_update() {
  local update_id="$1" status attempt=0
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  while true; do
    status="$(aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$update_id" --query update.status --output text)"
    case "$status" in
      Successful)
        info "update $update_id succeeded"
        return 0
        ;;
      Failed | Cancelled)
        aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$update_id" --query update.errors --output json >&2 || true
        die "update $update_id finished with status $status"
        ;;
    esac
    attempt=$((attempt + 1))
    if ((attempt >= UPDATE_POLL_ATTEMPTS)); then
      die "timed out waiting for update $update_id (last status: $status)"
    fi
    info "update $update_id is $status; waiting ${UPDATE_POLL_SECONDS}s"
    sleep "$UPDATE_POLL_SECONDS"
  done
}

setup_kubectl() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    KUBECTL=(kubectl --context "$KUBE_CONTEXT")
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    KUBECTL=(kubectl --kubeconfig "${TMPDIR:-/tmp}/nullify-eks-kubeconfig")
    mutate aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --kubeconfig "${KUBECTL[2]}"
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is required (or pass --skip-rbac)"
  fi
  KUBECONFIG_TMP="$(mktemp "${TMPDIR:-/tmp}/nullify-eks-kubeconfig.XXXXXX")"
  trap cleanup_tmp EXIT
  log "[run] aws eks update-kubeconfig --name $CLUSTER --region $REGION --kubeconfig $KUBECONFIG_TMP"
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --kubeconfig "$KUBECONFIG_TMP" >/dev/null
  KUBECTL=(kubectl --kubeconfig "$KUBECONFIG_TMP")
}

rbac_in_scope() {
  [[ "$AUTHORIZATION" == rbac && "$SKIP_RBAC" != true ]]
}

# use_release_rbac_manifest CHECKOUT_MANIFEST
# Downloads the manifest published at RBAC_MANIFEST_RELEASE_TAG once, to a
# temporary file that every later kubectl call reads, so what is applied or
# removed is what was fetched. Dies with the alternatives when that tag's file
# cannot be fetched (for example, the tag is not published yet).
use_release_rbac_manifest() {
  local unavailable="rbac: $1 is not in this checkout, and the manifest at release tag $RBAC_MANIFEST_RELEASE_TAG ($RBAC_MANIFEST_RELEASE_URL) could not be fetched; the tag may not be published yet. Pass --rbac-manifest PATH|URL with a copy you reviewed, or install the nullify-k8s-readonly-access Helm chart and re-run with --skip-rbac"
  local file
  if ! command -v curl >/dev/null 2>&1; then
    die "$unavailable (curl is not installed)"
  fi
  RBAC_MANIFEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nullify-readonly-rbac.XXXXXX")"
  trap cleanup_tmp EXIT
  file="$RBAC_MANIFEST_TMP_DIR/nullify-readonly-rbac.yaml"
  if ! curl --proto '=https' -fsSL --max-time 30 -o "$file" "$RBAC_MANIFEST_RELEASE_URL"; then
    die "$unavailable"
  fi
  RBAC_MANIFEST="$file"
  info "rbac: $1 is not in this checkout; using the manifest at release tag $RBAC_MANIFEST_RELEASE_TAG ($RBAC_MANIFEST_RELEASE_URL), downloaded once to $file. Review it, or pass --rbac-manifest PATH|URL"
}

check_rbac_manifest() {
  local checkout_manifest="$REPO_ROOT/manifests/nullify-readonly-rbac.yaml"
  if [[ -z "$RBAC_MANIFEST" ]]; then
    if [[ -f "$checkout_manifest" ]]; then
      RBAC_MANIFEST="$checkout_manifest"
    else
      use_release_rbac_manifest "$checkout_manifest"
    fi
    return 0
  fi
  case "$RBAC_MANIFEST" in
    https://*)
      if [[ ! "$RBAC_MANIFEST" =~ /[0-9a-f]{40}/ ]]; then
        warn "--rbac-manifest URL is not pinned to a commit SHA; review what it applies before running apply"
      fi
      ;;
    http://*)
      die "--rbac-manifest must use https"
      ;;
    *)
      if [[ ! -f "$RBAC_MANIFEST" ]]; then
        die "RBAC manifest not found: $RBAC_MANIFEST. Fix the --rbac-manifest path, omit --rbac-manifest to use the default, or install the nullify-k8s-readonly-access Helm chart and re-run with --skip-rbac"
      fi
      ;;
  esac
}

ensure_auth_mode() {
  local mode update_id
  mode="$(cluster_query accessConfig.authenticationMode)"
  case "$mode" in
    API | API_AND_CONFIG_MAP)
      info "authentication mode: $mode (supports access entries)"
      ;;
    CONFIG_MAP)
      if [[ "$ALLOW_AUTH_MODE_CHANGE" != true ]]; then
        local message="authentication mode is CONFIG_MAP, which cannot hold access entries. Switching to API_AND_CONFIG_MAP keeps aws-auth working but is one-way: EKS cannot switch back. Re-run with --allow-auth-mode-change to switch."
        if [[ "$DRY_RUN" == true ]]; then
          warn "$message"
          return 0
        fi
        die "$message"
      fi
      warn "switching authentication mode CONFIG_MAP -> API_AND_CONFIG_MAP (one-way)"
      update_id="$(mutate aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
        --access-config authenticationMode=API_AND_CONFIG_MAP --query update.id --output text)"
      wait_for_update "$update_id"
      ;;
    *)
      die "unexpected authentication mode '$mode'"
      ;;
  esac
}

access_entry_exists() {
  local found
  found="$(aws eks list-access-entries --cluster-name "$CLUSTER" --region "$REGION" \
    --query "accessEntries[?@ == '${ROLE_ARN}']" --output text)"
  [[ -n "$found" && "$found" != None ]]
}

access_entry_owner() {
  aws eks describe-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN" \
    --query "accessEntry.tags.${MANAGED_BY_TAG_KEY}" --output text
}

ensure_access_entry() {
  local owner
  local -a create
  if [[ "$SKIP_ACCESS_ENTRY" == true ]]; then
    info "access entry: skipped (--skip-access-entry)"
    return 0
  fi
  if access_entry_exists; then
    owner="$(access_entry_owner)"
    if [[ "$owner" != "$MANAGED_BY_TAG_VALUE" ]]; then
      warn "access entry for $ROLE_ARN exists and is not tagged ${MANAGED_BY_TAG_KEY}=${MANAGED_BY_TAG_VALUE} (found: $owner); leaving it unchanged"
      return 0
    fi
    info "access entry: already exists (created by this script)"
  else
    create=(aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION"
      --principal-arn "$ROLE_ARN" --type STANDARD
      --tags "${MANAGED_BY_TAG_KEY}=${MANAGED_BY_TAG_VALUE}")
    if [[ "$AUTHORIZATION" == rbac ]]; then
      create+=(--kubernetes-groups "$GROUP")
    fi
    mutate "${create[@]}" >/dev/null
  fi
  if [[ "$AUTHORIZATION" == admin-view ]]; then
    warn "$ADMIN_VIEW_WARNING"
    mutate aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" \
      --principal-arn "$ROLE_ARN" --policy-arn "$ADMIN_VIEW_POLICY_ARN" --access-scope type=cluster >/dev/null
  fi
}

apply_rbac() {
  if [[ "$AUTHORIZATION" != rbac ]]; then
    info "rbac: not needed (authorization admin-view)"
    return 0
  fi
  if [[ "$SKIP_RBAC" == true ]]; then
    info "rbac: skipped (--skip-rbac)"
    return 0
  fi
  check_rbac_manifest
  mutate "${KUBECTL[@]}" apply -f "$RBAC_MANIFEST"
  if [[ "$GROUP" != "$DEFAULT_GROUP" ]]; then
    warn "the manifest binds group $DEFAULT_GROUP. Bind ClusterRole $RBAC_CLUSTER_ROLE to group $GROUP yourself: kubectl create clusterrolebinding ${RBAC_CLUSTER_ROLE}-${GROUP} --clusterrole=${RBAC_CLUSTER_ROLE} --group=${GROUP}"
  fi
}

current_public_cidrs() {
  local raw
  raw="$(cluster_query resourcesVpcConfig.publicAccessCidrs)" || die "could not read publicAccessCidrs of $CLUSTER"
  raw="$(cidr_normalise "$raw")"
  if [[ "$raw" == None ]]; then
    raw=""
  fi
  echo "$raw"
}

cluster_tag_keys() {
  local raw query="keys(cluster.tags || \`{}\`)"
  raw="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query "$query" --output text)" ||
    die "could not read the tag keys of $CLUSTER"
  raw="$(cidr_normalise "$raw")"
  if [[ "$raw" == None ]]; then
    raw=""
  fi
  echo "$raw"
}

cidr_tag_value() {
  local raw
  raw="$(cluster_query "tags.\"$1\"")" || die "could not read the $1 tag of $CLUSTER"
  if [[ "$raw" == None ]]; then
    raw=""
  fi
  cidr_normalise "$raw"
}

# load_cidr_records
# Reads every part of the added and pending CIDR records into ADDED_CIDRS,
# ADDED_TAG_KEYS, PENDING_CIDRS and PENDING_TAG_KEYS. Dies when a read fails.
load_cidr_records() {
  local raw key value
  local -a keys
  ADDED_CIDRS=""
  ADDED_TAG_KEYS=""
  PENDING_CIDRS=""
  PENDING_TAG_KEYS=""
  raw="$(cluster_tag_keys)" || exit 1
  read -r -a keys <<< "$raw"
  for key in ${keys[@]+"${keys[@]}"}; do
    if cidr_tag_is_part "$ADDED_CIDRS_TAG_KEY" "$key"; then
      value="$(cidr_tag_value "$key")" || exit 1
      ADDED_CIDRS="$(cidr_union "$ADDED_CIDRS" "$value")"
      ADDED_TAG_KEYS="${ADDED_TAG_KEYS:+$ADDED_TAG_KEYS }$key"
    elif cidr_tag_is_part "$PENDING_CIDRS_TAG_KEY" "$key"; then
      value="$(cidr_tag_value "$key")" || exit 1
      PENDING_CIDRS="$(cidr_union "$PENDING_CIDRS" "$value")"
      PENDING_TAG_KEYS="${PENDING_TAG_KEYS:+$PENDING_TAG_KEYS }$key"
    fi
  done
}

# store_cidr_record BASE LIST EXISTING_KEYS
# Writes LIST under BASE, BASE-2, ... in one tag-resource call, no value longer
# than EKS allows, then untags the EXISTING_KEYS the new record no longer uses.
# Sets STORED_TAG_KEYS to the keys written.
store_cidr_record() {
  local base="$1" chunks chunk key tags="" index=0
  local -a existing written stale
  read -r -a existing <<< "${3:-}"
  written=()
  stale=()
  chunks="$(cidr_tag_chunks "$2" "$EKS_TAG_VALUE_MAX_LENGTH")" || die "cannot store '$2' in the $base tag"
  while IFS= read -r chunk; do
    if [[ -z "$chunk" ]]; then
      continue
    fi
    index=$((index + 1))
    key="$(cidr_tag_part_key "$base" "$index")"
    tags="${tags:+$tags,}\"${key}\":\"${chunk}\""
    written+=("$key")
  done <<< "$chunks"
  if [[ -n "$tags" ]]; then
    mutate aws eks tag-resource --resource-arn "$CLUSTER_ARN" --region "$REGION" --tags "{${tags}}" ||
      die "could not write the $base tag of $CLUSTER; re-run $ACTION"
  fi
  for key in ${existing[@]+"${existing[@]}"}; do
    if ! cidr_list_contains "$key" ${written[@]+"${written[@]}"}; then
      stale+=("$key")
    fi
  done
  if ((${#stale[@]} > 0)); then
    drop_cidr_tags "${stale[*]}"
  fi
  STORED_TAG_KEYS="${written[*]:-}"
}

drop_cidr_tags() {
  local -a keys
  read -r -a keys <<< "${1:-}"
  if ((${#keys[@]} == 0)); then
    return 0
  fi
  mutate aws eks untag-resource --resource-arn "$CLUSTER_ARN" --region "$REGION" --tag-keys "${keys[@]}" ||
    die "could not remove the tags ${keys[*]} of $CLUSTER; re-run $ACTION"
}

# require_no_endpoint_update_in_progress
# Dies when an EndpointAccessUpdate of the cluster is InProgress. EKS moves the
# cluster status to UPDATING only eventually, so ACTIVE does not prove a stopped
# run's update has finished, and publicAccessCidrs may not show it yet. Callers
# run this before reading the CIDRs a pending record is settled against. Every
# update id is described, because list-updates does not document an order.
require_no_endpoint_update_in_progress() {
  local raw id details update_type update_status
  local -a ids
  raw="$(aws eks list-updates --name "$CLUSTER" --region "$REGION" --query updateIds --output text)" ||
    die "could not list the updates of $CLUSTER (needs eks:ListUpdates); publicAccessCidrs and the ${PENDING_CIDRS_TAG_KEY} record were left unchanged"
  raw="$(cidr_normalise "$raw")"
  if [[ "$raw" == None ]]; then
    raw=""
  fi
  read -r -a ids <<< "$raw"
  for id in ${ids[@]+"${ids[@]}"}; do
    details="$(aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$id" \
      --query 'update.[type, status]' --output text)" ||
      die "could not describe update $id of $CLUSTER; publicAccessCidrs and the ${PENDING_CIDRS_TAG_KEY} record were left unchanged"
    read -r update_type update_status <<< "$(cidr_normalise "$details")"
    if [[ "$update_type" == EndpointAccessUpdate && "$update_status" == InProgress ]]; then
      die "endpoint access update $id of $CLUSTER is still InProgress, so publicAccessCidrs may not show it yet; publicAccessCidrs and the ${PENDING_CIDRS_TAG_KEY} record were left unchanged. Re-run $ACTION when it finishes: aws eks describe-update --name $CLUSTER --region $REGION --update-id $id"
    fi
  done
}

# cidr_tag_part_count LIST
# Prints how many tags (BASE, BASE-2, ...) store_cidr_record writes for LIST.
cidr_tag_part_count() {
  local chunks
  chunks="$(cidr_tag_chunks "$1" "$EKS_TAG_VALUE_MAX_LENGTH")" || die "cannot store '$1' in a tag"
  if [[ -z "$chunks" ]]; then
    echo 0
    return 0
  fi
  printf '%s\n' "$chunks" | wc -l | tr -d ' '
}

# new_tag_parts LIST EXISTING_KEYS
# Prints how many tags storing LIST adds beyond the EXISTING_KEYS it replaces.
new_tag_parts() {
  local parts
  local -a existing
  parts="$(cidr_tag_part_count "$1")" || exit 1
  read -r -a existing <<< "${2:-}"
  if ((parts > ${#existing[@]})); then
    echo $((parts - ${#existing[@]}))
  else
    echo 0
  fi
}

# require_free_tag_slots NEEDED PURPOSE
# Dies when fewer than NEEDED of the tags EKS allows per resource are free. Keys
# starting with aws: do not count towards the limit.
require_free_tag_slots() {
  local needed="$1" used free
  if ((needed <= 0)); then
    return 0
  fi
  used="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
    --query "length(keys(cluster.tags || \`{}\`)[?!starts_with(@, 'aws:')])" --output text)" ||
    die "could not count the tags of $CLUSTER"
  if [[ ! "$used" =~ ^[0-9]+$ ]]; then
    die "could not count the tags of $CLUSTER (got '$used')"
  fi
  free=$((EKS_MAX_TAGS_PER_RESOURCE - used))
  if ((free < needed)); then
    die "$CLUSTER has $used tags and EKS allows at most $EKS_MAX_TAGS_PER_RESOURCE per resource; $2 needs $needed free tag(s). Remove $((needed - free)) tag(s) from the cluster and re-run $ACTION. publicAccessCidrs and the CIDR records were left unchanged"
  fi
}

# reconcile_pending_cidrs CURRENT
# Settles a pending record left by a run that stopped after writing it: its
# CIDRs present in CURRENT were added by that run's update and move to the added
# record, and the rest never landed and are dropped. The caller reads CURRENT
# after require_no_endpoint_update_in_progress, so that update has finished.
reconcile_pending_cidrs() {
  local landed needed
  if [[ -z "$PENDING_TAG_KEYS" ]]; then
    return 0
  fi
  landed="$(cidr_intersect "$PENDING_CIDRS" "$1")"
  if [[ -n "$landed" ]]; then
    info "network: a previous run added $landed to publicAccessCidrs without recording it; recording it in ${ADDED_CIDRS_TAG_KEY}"
    ADDED_CIDRS="$(cidr_union "$ADDED_CIDRS" "$landed")"
    needed="$(new_tag_parts "$ADDED_CIDRS" "$ADDED_TAG_KEYS")" || exit 1
    require_free_tag_slots "$needed" "recording $landed in ${ADDED_CIDRS_TAG_KEY}"
    store_cidr_record "$ADDED_CIDRS_TAG_KEY" "$ADDED_CIDRS" "$ADDED_TAG_KEYS"
    ADDED_TAG_KEYS="$STORED_TAG_KEYS"
  fi
  drop_cidr_tags "$PENDING_TAG_KEYS"
  PENDING_CIDRS=""
  PENDING_TAG_KEYS=""
}

# endpoint_access_json FIELD
# Prints resourcesVpcConfig.FIELD (endpointPublicAccess or endpointPrivateAccess)
# as a JSON boolean, and dies when it cannot be read.
endpoint_access_json() {
  local value
  value="$(cluster_query "resourcesVpcConfig.$1")" || die "could not read $1 of $CLUSTER"
  case "$value" in
    True) echo true ;;
    False) echo false ;;
    *) die "could not read $1 of $CLUSTER (got '$value')" ;;
  esac
}

# update_public_cidrs DESIRED EXPECTED_CURRENT [PENDING]
# Re-reads publicAccessCidrs and both endpoint flags immediately before the
# update, aborts if the CIDRs no longer match what the caller planned against or
# the public endpoint is now disabled, and sends the flags as read so neither is
# changed. PENDING, when given, is recorded in the pending tag just before
# update-cluster-config.
update_public_cidrs() {
  local desired="$1" expected="$2" pending="${3:-}" latest public private vpc_config update_id
  latest="$(current_public_cidrs)"
  if [[ "$latest" != "$expected" ]]; then
    die "publicAccessCidrs changed while this script ran (was: ${expected:-empty}, now: ${latest:-empty}); re-run"
  fi
  public="$(endpoint_access_json endpointPublicAccess)"
  if [[ "$public" != true ]]; then
    die "the public endpoint of $CLUSTER is disabled; publicAccessCidrs left unchanged"
  fi
  private="$(endpoint_access_json endpointPrivateAccess)"
  vpc_config="$(printf '{"endpointPublicAccess":%s,"endpointPrivateAccess":%s,"publicAccessCidrs":%s}' \
    "$public" "$private" "$(cidr_json_array "$desired")")"
  if [[ -n "$pending" ]]; then
    store_cidr_record "$PENDING_CIDRS_TAG_KEY" "$pending" "$PENDING_TAG_KEYS"
    PENDING_CIDRS="$pending"
    PENDING_TAG_KEYS="$STORED_TAG_KEYS"
  fi
  update_id="$(mutate aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
    --resources-vpc-config "$vpc_config" --query update.id --output text)"
  wait_for_update "$update_id"
}

ensure_network() {
  local public current merged added unrecorded pending_parts added_parts
  if [[ "$SKIP_NETWORK" == true ]]; then
    info "network: skipped (--skip-network)"
    return 0
  fi
  public="$(endpoint_access_json endpointPublicAccess)"
  if [[ "$public" != true ]]; then
    die "cluster $CLUSTER has no public endpoint. Private-only clusters are not supported by the managed scan: enable the public endpoint restricted to Nullify's egress IPs, or use the in-cluster collector"
  fi
  load_cidr_records
  if [[ -n "$PENDING_TAG_KEYS" ]]; then
    require_no_endpoint_update_in_progress
  fi
  current="$(current_public_cidrs)"
  reconcile_pending_cidrs "$current"
  if ! merged="$(cidr_merge "$current" "$NULLIFY_CIDRS")"; then
    die "cannot add Nullify egress IPs ($NULLIFY_CIDRS) to publicAccessCidrs (${current:-empty})"
  fi
  added="$(cidr_missing "$current" "$merged")"
  if [[ -z "$added" ]]; then
    info "network: publicAccessCidrs already admits Nullify (${current})"
    unrecorded="$(cidr_difference "$(cidr_intersect "$NULLIFY_CIDRS" "$current")" "$ADDED_CIDRS")"
    if [[ -n "$unrecorded" ]]; then
      warn "network: $unrecorded is not recorded in ${ADDED_CIDRS_TAG_KEY}, so remove will leave it in publicAccessCidrs. If this script added it, record it with: aws eks tag-resource --resource-arn $CLUSTER_ARN --region $REGION --tags '{\"${ADDED_CIDRS_TAG_KEY}\":\"$(cidr_union "$ADDED_CIDRS" "$unrecorded")\"}'"
    fi
    return 0
  fi
  pending_parts="$(cidr_tag_part_count "$added")" || exit 1
  added_parts="$(new_tag_parts "$(cidr_union "$ADDED_CIDRS" "$added")" "$ADDED_TAG_KEYS")" || exit 1
  require_free_tag_slots $((pending_parts + added_parts)) "recording $added in ${PENDING_CIDRS_TAG_KEY} and then ${ADDED_CIDRS_TAG_KEY}"
  info "network: adding $added to publicAccessCidrs"
  update_public_cidrs "$merged" "$current" "$added"
  ADDED_CIDRS="$(cidr_union "$ADDED_CIDRS" "$added")"
  store_cidr_record "$ADDED_CIDRS_TAG_KEY" "$ADDED_CIDRS" "$ADDED_TAG_KEYS"
  ADDED_TAG_KEYS="$STORED_TAG_KEYS"
  drop_cidr_tags "$PENDING_TAG_KEYS"
  PENDING_CIDRS=""
  PENDING_TAG_KEYS=""
}

remove_rbac() {
  local objects object owner managed_by release
  if ! rbac_in_scope; then
    info "rbac: nothing to remove (authorization admin-view or --skip-rbac)"
    return 0
  fi
  check_rbac_manifest
  if [[ "$DRY_RUN" == true && -z "$KUBE_CONTEXT" ]]; then
    mutate "${KUBECTL[@]}" delete --ignore-not-found -f "$RBAC_MANIFEST"
    info "rbac: remove skips objects labelled app.kubernetes.io/managed-by=Helm or annotated meta.helm.sh/release-name"
    return 0
  fi
  objects="$("${KUBECTL[@]}" get --ignore-not-found -f "$RBAC_MANIFEST" -o name)" ||
    die "could not read the objects of $RBAC_MANIFEST from the cluster"
  if [[ -z "$objects" ]]; then
    info "rbac: none of the objects in $RBAC_MANIFEST exist"
    return 0
  fi
  for object in $objects; do
    owner="$("${KUBECTL[@]}" get --ignore-not-found "$object" \
      -o 'jsonpath={.metadata.labels.app\.kubernetes\.io/managed-by}{"|"}{.metadata.annotations.meta\.helm\.sh/release-name}')" ||
      die "could not read $object"
    managed_by="${owner%%"|"*}"
    release="${owner#*"|"}"
    if [[ "$managed_by" == Helm || -n "$release" ]]; then
      warn "rbac: leaving $object: it is managed by Helm (release ${release:-unknown}); remove it with helm uninstall, or pass --skip-rbac"
      continue
    fi
    mutate "${KUBECTL[@]}" delete --ignore-not-found "$object"
  done
}

remove_access_entry() {
  local owner
  if [[ "$SKIP_ACCESS_ENTRY" == true ]]; then
    info "access entry: skipped (--skip-access-entry)"
    return 0
  fi
  if ! access_entry_exists; then
    info "access entry: none for $ROLE_ARN"
    return 0
  fi
  owner="$(access_entry_owner)"
  if [[ "$owner" != "$MANAGED_BY_TAG_VALUE" ]]; then
    warn "access entry for $ROLE_ARN is not tagged ${MANAGED_BY_TAG_KEY}=${MANAGED_BY_TAG_VALUE} (found: $owner); leaving it. Delete the CloudFormation access stack if it owns the entry."
    return 0
  fi
  mutate aws eks delete-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN"
}

remove_network() {
  local public current owned remaining
  if [[ "$SKIP_NETWORK" == true ]]; then
    info "network: skipped (--skip-network)"
    return 0
  fi
  load_cidr_records
  if [[ -z "$ADDED_TAG_KEYS" && -z "$PENDING_TAG_KEYS" ]]; then
    info "network: no ${ADDED_CIDRS_TAG_KEY} or ${PENDING_CIDRS_TAG_KEY} tag; publicAccessCidrs left unchanged"
    return 0
  fi
  public="$(endpoint_access_json endpointPublicAccess)"
  if [[ "$public" != true ]]; then
    warn "network: the public endpoint of $CLUSTER is disabled; leaving the endpoint, publicAccessCidrs and the ${ADDED_CIDRS_TAG_KEY}/${PENDING_CIDRS_TAG_KEY} tags unchanged. publicAccessCidrs can still hold Nullify's CIDRs when the public endpoint is re-enabled; re-run remove then to take them out"
    return 0
  fi
  if [[ -n "$PENDING_TAG_KEYS" ]]; then
    require_no_endpoint_update_in_progress
  fi
  current="$(current_public_cidrs)"
  owned="$(cidr_union "$ADDED_CIDRS" "$(cidr_intersect "$PENDING_CIDRS" "$current")")"
  remaining="$current"
  if [[ -n "$owned" ]]; then
    if ! remaining="$(cidr_remove "$current" "$owned")"; then
      die "removing $owned would leave publicAccessCidrs empty. Add the CIDRs you want to keep, or disable the public endpoint, then re-run"
    fi
  fi
  if [[ "$remaining" != "$current" ]]; then
    info "network: removing $owned from publicAccessCidrs"
    update_public_cidrs "$remaining" "$current"
  else
    info "network: none of the recorded CIDRs are in publicAccessCidrs"
  fi
  drop_cidr_tags "$ADDED_TAG_KEYS $PENDING_TAG_KEYS"
}

check_pass() { log "[PASS] $*"; }
check_fail() {
  log "[FAIL] $*"
  VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
}

verify_access_entry() {
  local mode groups scope
  mode="$(cluster_query accessConfig.authenticationMode)"
  case "$mode" in
    API | API_AND_CONFIG_MAP) check_pass "authentication mode $mode supports access entries" ;;
    *) check_fail "authentication mode $mode does not support access entries" ;;
  esac
  if ! access_entry_exists; then
    check_fail "no access entry for $ROLE_ARN"
    return 0
  fi
  check_pass "access entry exists for $ROLE_ARN"
  groups="$(aws eks describe-access-entry --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN" \
    --query accessEntry.kubernetesGroups --output text)"
  groups="$(cidr_normalise "$groups")"
  scope="$(aws eks list-associated-access-policies --cluster-name "$CLUSTER" --region "$REGION" --principal-arn "$ROLE_ARN" \
    --query "associatedAccessPolicies[?policyArn == '${ADMIN_VIEW_POLICY_ARN}'].accessScope.type" --output text)"
  if [[ "$scope" == None ]]; then
    scope=""
  fi
  if [[ "$AUTHORIZATION" == rbac ]]; then
    if [[ " $groups " == *" $GROUP "* ]]; then
      check_pass "access entry carries Kubernetes group $GROUP"
    else
      check_fail "access entry groups (${groups:-none}) do not include $GROUP"
    fi
    if [[ -n "$scope" ]]; then
      warn "AmazonEKSAdminViewPolicy is also associated, which is broader than rbac mode needs"
    fi
  elif [[ "$scope" == cluster ]]; then
    check_pass "AmazonEKSAdminViewPolicy is associated with cluster scope"
  else
    check_fail "AmazonEKSAdminViewPolicy is not associated with cluster scope (found: ${scope:-none})"
  fi
}

verify_rbac() {
  local resource answer
  if [[ "$AUTHORIZATION" != rbac ]]; then
    info "rbac: kubectl auth can-i cannot see access-policy grants; admin-view is checked through list-associated-access-policies only"
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    check_fail "kubectl is not installed; cannot check RBAC"
    return 0
  fi
  setup_kubectl
  for resource in "${RBAC_RESOURCES[@]}"; do
    answer="$("${KUBECTL[@]}" auth can-i list "$resource" --all-namespaces --as "$VERIFY_USER" --as-group "$GROUP" 2>/dev/null || true)"
    if [[ "$answer" == yes* ]]; then
      check_pass "group $GROUP can list $resource"
    else
      check_fail "group $GROUP cannot list $resource (got: ${answer:-no answer})"
    fi
  done
  answer="$("${KUBECTL[@]}" auth can-i create pods --all-namespaces --as "$VERIFY_USER" --as-group "$GROUP" 2>/dev/null || true)"
  if [[ "$answer" == yes* ]]; then
    check_fail "group $GROUP can create pods; the grant must be read-only"
  else
    check_pass "group $GROUP cannot create pods"
  fi
  info "kubectl auth can-i impersonates the group through Kubernetes RBAC only: it does not exercise EKS access policies or prove Nullify can reach the endpoint"
}

verify_network() {
  local public current missing
  if [[ "$SKIP_NETWORK" == true ]]; then
    info "network: skipped (--skip-network)"
    return 0
  fi
  public="$(cluster_query resourcesVpcConfig.endpointPublicAccess)"
  if [[ "$public" != True ]]; then
    check_fail "public endpoint is disabled; private-only clusters are not supported by the managed scan"
    return 0
  fi
  current="$(current_public_cidrs)"
  missing="$(cidr_missing "$current" "$NULLIFY_CIDRS")"
  if [[ -z "$missing" ]]; then
    check_pass "publicAccessCidrs admits Nullify's $NULLIFY_REGION egress IPs"
  else
    check_fail "publicAccessCidrs is missing Nullify egress IPs: $missing"
  fi
}

run_verify() {
  verify_access_entry
  verify_rbac
  verify_network
  info "end to end: confirm the cluster connects on the Nullify configure page"
  if ((VERIFY_FAILURES > 0)); then
    die "verify: $VERIFY_FAILURES check(s) failed"
  fi
  info "verify: all checks passed"
}

main() {
  parse_args "$@"
  preflight
  case "$ACTION" in
    plan | apply)
      ensure_auth_mode
      ensure_access_entry
      if rbac_in_scope; then
        setup_kubectl
      fi
      apply_rbac
      ensure_network
      if [[ "$DRY_RUN" == true ]]; then
        info "dry run complete: nothing was changed"
      else
        info "apply complete; check it with: $(basename "$0") verify --cluster $CLUSTER --region $REGION ..."
      fi
      ;;
    verify)
      run_verify
      ;;
    remove)
      if rbac_in_scope; then
        setup_kubectl
      fi
      remove_rbac
      remove_access_entry
      remove_network
      ;;
  esac
}

main "$@"
