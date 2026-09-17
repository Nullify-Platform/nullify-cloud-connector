#!/usr/bin/env bats
# Tests for cleanup.sh --method cloudformation against the fake AWS CLI in
# tests/stubs/aws. No AWS account is used.
# Run from the repository root: bats aws-integration-setup/scripts/tests

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../cleanup.sh"
  PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  FAKE_AWS_LOG="$(mktemp "${BATS_TMPDIR:-/tmp}/fake-aws-log.XXXXXX")"
  FAKE_STS_FAILS=false
  FAKE_CFN_STACKS=""
  FAKE_CFN_DENIED_REGION=""
  FAKE_CFN_ALL_DENIED=false
  export PATH FAKE_AWS_LOG FAKE_STS_FAILS FAKE_CFN_STACKS FAKE_CFN_DENIED_REGION FAKE_CFN_ALL_DENIED
}

teardown() {
  rm -f "$FAKE_AWS_LOG"
}

run_cleanup() {
  run bash "$SCRIPT" --method cloudformation --stack-name nullify-integration --yes "$@"
}

called() {
  grep -q -F -- "$1" "$FAKE_AWS_LOG"
}

not_called() {
  ! grep -q -F -- "$1" "$FAKE_AWS_LOG"
}

output_lacks() {
  case "$output" in
    *"$1"*) return 1 ;;
  esac
  return 0
}

output_has() {
  ! output_lacks "$1"
}

@test "expired credentials stop cleanup before any stack is checked or deleted" {
  FAKE_STS_FAILS=true
  run_cleanup --eks-access-regions eu-west-1
  [ "$status" -ne 0 ]
  not_called 'cloudformation'
  output_lacks "Cleanup complete"
}

@test "access denied on an access stack stops cleanup without skipping it or claiming success" {
  FAKE_CFN_STACKS="nullify-integration@"
  FAKE_CFN_DENIED_REGION=eu-west-1
  run_cleanup --eks-access-regions eu-west-1
  [ "$status" -ne 0 ]
  not_called 'cloudformation delete-stack'
  output_has "Could not check stack"
  output_lacks "skipping"
  output_lacks "Cleanup complete"
}

@test "access denied on the main stack stops cleanup without reporting it missing" {
  FAKE_CFN_ALL_DENIED=true
  run_cleanup
  [ "$status" -ne 0 ]
  not_called 'cloudformation delete-stack'
  output_lacks "Nothing to clean up"
  output_lacks "Cleanup complete"
}

@test "a main stack that does not exist is reported as nothing to clean up" {
  run_cleanup
  [ "$status" -eq 0 ]
  not_called 'cloudformation delete-stack'
  output_has "Nothing to clean up"
}

@test "--region is used to check, delete and wait for the main stack" {
  FAKE_CFN_STACKS="nullify-integration@eu-west-1"
  run_cleanup --region eu-west-1
  [ "$status" -eq 0 ]
  called 'cloudformation describe-stacks --stack-name nullify-integration --region eu-west-1'
  called 'cloudformation delete-stack --region eu-west-1 --stack-name nullify-integration'
  called 'cloudformation wait stack-delete-complete --region eu-west-1 --stack-name nullify-integration'
  output_has "Cleanup complete"
}

@test "a main stack not found names the region that was checked" {
  FAKE_CFN_STACKS="nullify-integration@eu-west-1"
  run_cleanup --region us-east-1
  [ "$status" -eq 0 ]
  not_called 'cloudformation delete-stack'
  output_has "not found in us-east-1"

  run_cleanup
  [ "$status" -eq 0 ]
  output_has "not found in the AWS CLI's configured region"
}

@test "only a does-not-exist error reads as a missing stack, and the rest are still deleted" {
  FAKE_CFN_STACKS="nullify-eks-managed-scan-access@us-east-1"
  run_cleanup --eks-access-regions eu-west-1,us-east-1
  [ "$status" -eq 0 ]
  not_called 'delete-stack --region eu-west-1'
  called 'cloudformation delete-stack --region us-east-1 --stack-name nullify-eks-managed-scan-access'
  not_called 'delete-stack --stack-name nullify-integration'
  output_has "deleted 1 EKS access stack(s)"
}
