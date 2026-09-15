#!/usr/bin/env bats
# Call-order tests for setup-eks-managed-scan.sh's publicAccessCidrs handling,
# run against the fake AWS CLI in tests/stubs/aws. No AWS account is used.
# Run from the repository root: bats aws-integration-setup/scripts/tests

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../setup-eks-managed-scan.sh"
  PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  FAKE_AWS_LOG="$(mktemp "${BATS_TMPDIR:-/tmp}/fake-aws-log.XXXXXX")"
  FAKE_PUBLIC=True
  FAKE_PRIVATE=False
  FAKE_CIDRS="203.0.113.0/24"
  FAKE_TAG=None
  FAKE_UPDATE_STATUS=Successful
  FAKE_CIDRS_READ_FAILS=false
  export PATH FAKE_AWS_LOG FAKE_PUBLIC FAKE_PRIVATE FAKE_CIDRS FAKE_TAG FAKE_UPDATE_STATUS FAKE_CIDRS_READ_FAILS
}

teardown() {
  rm -f "$FAKE_AWS_LOG"
}

run_setup() {
  local action="$1"
  shift
  run bash "$SCRIPT" "$action" --cluster prod --region eu-west-1 --customer-name acme \
    --skip-access-entry --skip-rbac "$@"
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

@test "apply tags nullify-added-cidrs only after the CIDR update succeeds" {
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  called '"publicAccessCidrs":["203.0.113.0/24","18.198.60.231/32","18.157.227.250/32","18.185.152.197/32"]'
  called 'nullify-added-cidrs":"18.198.60.231/32 18.157.227.250/32 18.185.152.197/32"'
  [ "$(call_line 'eks describe-update')" -lt "$(call_line 'eks tag-resource')" ]
}

@test "apply does not tag when the CIDR update fails" {
  FAKE_UPDATE_STATUS=Failed
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  called 'eks update-cluster-config'
  not_called 'eks tag-resource'
}

@test "apply stops before any change when publicAccessCidrs cannot be read" {
  FAKE_CIDRS_READ_FAILS=true
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
}

@test "remove drops only the recorded CIDRs and keeps the endpoint flags as read" {
  FAKE_PRIVATE=True
  FAKE_CIDRS="203.0.113.0/24 18.198.60.231/32"
  FAKE_TAG="18.198.60.231/32"
  run_setup remove
  [ "$status" -eq 0 ]
  called '{"endpointPublicAccess":true,"endpointPrivateAccess":true,"publicAccessCidrs":["203.0.113.0/24"]}'
  [ "$(call_line 'eks describe-update')" -lt "$(call_line 'eks untag-resource')" ]
}

@test "remove leaves a disabled public endpoint unchanged and only drops the tag" {
  FAKE_PUBLIC=False
  FAKE_CIDRS="203.0.113.0/24 18.198.60.231/32"
  FAKE_TAG="18.198.60.231/32"
  run_setup remove
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  called 'eks untag-resource'
}
