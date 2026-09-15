#!/usr/bin/env bats
# Call-order and crash-recovery tests for setup-eks-managed-scan.sh's
# publicAccessCidrs handling, run against the stateful fake AWS CLI in
# tests/stubs/aws. No AWS account is used.
# Run from the repository root: bats aws-integration-setup/scripts/tests

NULLIFY_EU="18.198.60.231/32 18.157.227.250/32 18.185.152.197/32"
BASE_CIDR="203.0.113.0/24"

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../setup-eks-managed-scan.sh"
  PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  FAKE_AWS_LOG="$(mktemp "${BATS_TMPDIR:-/tmp}/fake-aws-log.XXXXXX")"
  FAKE_AWS_STATE="$(mktemp -d "${BATS_TMPDIR:-/tmp}/fake-aws-state.XXXXXX")"
  FAKE_PUBLIC=True
  FAKE_PRIVATE=False
  FAKE_UPDATE_STATUS=Successful
  FAKE_CIDRS_READ_FAILS=false
  FAKE_DESCRIBE_UPDATE_FAILS=false
  export PATH FAKE_AWS_LOG FAKE_AWS_STATE FAKE_PUBLIC FAKE_PRIVATE FAKE_UPDATE_STATUS \
    FAKE_CIDRS_READ_FAILS FAKE_DESCRIBE_UPDATE_FAILS
  mkdir -p "$FAKE_AWS_STATE/tags"
  set_cidrs "$BASE_CIDR"
}

teardown() {
  rm -rf "$FAKE_AWS_LOG" "$FAKE_AWS_STATE"
}

run_setup() {
  local action="$1"
  shift
  run bash "$SCRIPT" "$action" --cluster prod --region eu-west-1 --customer-name acme \
    --skip-access-entry --skip-rbac "$@"
}

set_cidrs() {
  printf '%s\n' "$1" >"$FAKE_AWS_STATE/cidrs"
}

live_cidrs() {
  cat "$FAKE_AWS_STATE/cidrs"
}

set_tag() {
  printf '%s' "$2" >"$FAKE_AWS_STATE/tags/$1"
}

tag_value() {
  cat "$FAKE_AWS_STATE/tags/$1"
}

no_tag() {
  [ ! -f "$FAKE_AWS_STATE/tags/$1" ]
}

call_line() {
  grep -n -F -- "$1" "$FAKE_AWS_LOG" | head -n 1 | cut -d: -f1
}

called() {
  grep -q -F -- "$1" "$FAKE_AWS_LOG"
}

not_called() {
  ! grep -q -F -- "$1" "$FAKE_AWS_LOG"
}

output_has() {
  case "$output" in
    *"$1"*) return 0 ;;
  esac
  return 1
}

@test "apply records pending CIDRs before the update and moves them to nullify-added-cidrs after Successful" {
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  called '{"endpointPublicAccess":true,"endpointPrivateAccess":false,"publicAccessCidrs":["203.0.113.0/24","18.198.60.231/32","18.157.227.250/32","18.185.152.197/32"]}'
  [ "$(live_cidrs)" = "$BASE_CIDR $NULLIFY_EU" ]
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs
  [ "$(call_line '"nullify-pending-cidrs":')" -lt "$(call_line 'eks update-cluster-config')" ]
  [ "$(call_line 'eks update-cluster-config')" -lt "$(call_line 'eks describe-update')" ]
  [ "$(call_line 'eks describe-update')" -lt "$(call_line '"nullify-added-cidrs":')" ]
  [ "$(call_line '"nullify-added-cidrs":')" -lt "$(call_line 'eks untag-resource')" ]
}

@test "a failed update leaves only a pending record, which the next apply drops" {
  FAKE_UPDATE_STATUS=Failed
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  [ "$(tag_value nullify-pending-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-added-cidrs

  FAKE_UPDATE_STATUS=Successful
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR $NULLIFY_EU" ]
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs
}

@test "apply stops before any change when publicAccessCidrs cannot be read" {
  FAKE_CIDRS_READ_FAILS=true
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  not_called 'eks untag-resource'
}

@test "apply that stops after the update is accepted keeps a pending record that a re-run promotes and remove undoes" {
  FAKE_DESCRIBE_UPDATE_FAILS=true
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR $NULLIFY_EU" ]
  [ "$(tag_value nullify-pending-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-added-cidrs

  FAKE_DESCRIBE_UPDATE_FAILS=false
  : >"$FAKE_AWS_LOG"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs

  run_setup remove
  [ "$status" -eq 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  no_tag nullify-added-cidrs
}

@test "re-running apply promotes live pending CIDRs and drops the ones that never landed" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  set_tag nullify-pending-cidrs "$NULLIFY_EU 198.51.100.7/32"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs
  [ "$(call_line '"nullify-added-cidrs":')" -lt "$(call_line 'eks untag-resource')" ]
}

@test "apply warns when Nullify's CIDRs are live but not recorded" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  output_has "is not recorded in nullify-added-cidrs"
}

@test "apply rewrites a split record into the parts it needs and untags the stale part" {
  set_tag nullify-added-cidrs "198.51.100.7/32"
  set_tag nullify-added-cidrs-2 "198.51.100.8/32"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  [ "$(tag_value nullify-added-cidrs)" = "198.51.100.7/32 198.51.100.8/32 $NULLIFY_EU" ]
  no_tag nullify-added-cidrs-2
  no_tag nullify-pending-cidrs
}

@test "apply splits a record longer than 256 characters across numbered tags" {
  local recorded="" i
  for ((i = 100; i < 114; i++)); do
    recorded="${recorded:+$recorded }198.51.100.${i}/32"
  done
  set_tag nullify-added-cidrs "$recorded"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  [ "$(tag_value nullify-added-cidrs) $(tag_value nullify-added-cidrs-2)" = "$recorded $NULLIFY_EU" ]
  no_tag nullify-added-cidrs-3

  run_setup remove
  [ "$status" -eq 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  no_tag nullify-added-cidrs
  no_tag nullify-added-cidrs-2
}

@test "remove takes out live CIDRs recorded only in nullify-pending-cidrs" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  set_tag nullify-pending-cidrs "$NULLIFY_EU"
  run_setup remove
  [ "$status" -eq 0 ]
  called '"publicAccessCidrs":["203.0.113.0/24"]'
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  no_tag nullify-pending-cidrs
  [ "$(call_line 'eks describe-update')" -lt "$(call_line 'eks untag-resource')" ]
}

@test "remove drops only the recorded CIDRs and keeps the endpoint flags as read" {
  FAKE_PRIVATE=True
  set_cidrs "$BASE_CIDR 18.198.60.231/32"
  set_tag nullify-added-cidrs "18.198.60.231/32"
  run_setup remove
  [ "$status" -eq 0 ]
  called '{"endpointPublicAccess":true,"endpointPrivateAccess":true,"publicAccessCidrs":["203.0.113.0/24"]}'
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  no_tag nullify-added-cidrs
  [ "$(call_line 'eks describe-update')" -lt "$(call_line 'eks untag-resource')" ]
}

@test "remove on a disabled public endpoint keeps publicAccessCidrs and both tags, and says so" {
  FAKE_PUBLIC=False
  set_cidrs "$BASE_CIDR 18.198.60.231/32"
  set_tag nullify-added-cidrs "18.198.60.231/32"
  set_tag nullify-pending-cidrs "18.157.227.250/32"
  run_setup remove
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  not_called 'eks untag-resource'
  [ "$(tag_value nullify-added-cidrs)" = "18.198.60.231/32" ]
  [ "$(tag_value nullify-pending-cidrs)" = "18.157.227.250/32" ]
  output_has "tags unchanged"
}
