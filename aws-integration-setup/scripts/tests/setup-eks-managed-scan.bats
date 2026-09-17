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
  FAKE_UPDATES=""
  FAKE_ADMIN_VIEW_SCOPE=""
  FAKE_CAN_I_YES=""
  unset FAKE_ASSOCIATED_POLICIES FAKE_KUBERNETES_GROUPS
  export PATH FAKE_AWS_LOG FAKE_AWS_STATE FAKE_PUBLIC FAKE_PRIVATE FAKE_UPDATE_STATUS \
    FAKE_CIDRS_READ_FAILS FAKE_DESCRIBE_UPDATE_FAILS FAKE_UPDATES FAKE_ADMIN_VIEW_SCOPE \
    FAKE_CAN_I_YES
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
  no_tag nullify-pending-update
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

@test "remove keeps a pending record while an endpoint access update is InProgress, and settles it once the update finishes" {
  set_tag nullify-pending-cidrs "$NULLIFY_EU"
  FAKE_UPDATES="update-6:VersionUpdate:Successful update-7:EndpointAccessUpdate:InProgress"
  run_setup remove
  [ "$status" -ne 0 ]
  output_has "update-7 of prod is still InProgress"
  called 'eks list-updates --name prod --region eu-west-1'
  not_called 'cluster.resourcesVpcConfig.publicAccessCidrs'
  not_called 'eks update-cluster-config'
  not_called 'eks untag-resource'
  [ "$(tag_value nullify-pending-cidrs)" = "$NULLIFY_EU" ]

  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_UPDATES="update-6:VersionUpdate:Successful update-7:EndpointAccessUpdate:Successful"
  run_setup remove
  [ "$status" -eq 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  no_tag nullify-pending-cidrs
}

@test "apply keeps a pending record while an endpoint access update is InProgress" {
  set_tag nullify-pending-cidrs "$NULLIFY_EU"
  FAKE_UPDATES="update-7:EndpointAccessUpdate:InProgress"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  output_has "update-7 of prod is still InProgress"
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  not_called 'eks untag-resource'
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
  [ "$(tag_value nullify-pending-cidrs)" = "$NULLIFY_EU" ]
}

@test "apply records the id of the update its pending record was written for" {
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  called '"nullify-pending-update":"update-1"'
  [ "$(call_line 'eks update-cluster-config')" -lt "$(call_line '"nullify-pending-update":')" ]
  [ "$(call_line '"nullify-pending-update":')" -lt "$(call_line 'eks describe-update')" ]
  no_tag nullify-pending-update
}

@test "a pending record naming an InProgress update stops apply without listing every update" {
  set_tag nullify-pending-cidrs "$NULLIFY_EU"
  set_tag nullify-pending-update "update-9"
  FAKE_UPDATES="update-9:EndpointAccessUpdate:InProgress"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  output_has "update-9 of prod is still InProgress"
  not_called 'eks list-updates'
  not_called 'eks update-cluster-config'
  not_called 'eks untag-resource'
  [ "$(tag_value nullify-pending-update)" = "update-9" ]
}

@test "a recorded update EKS no longer knows about does not stop apply" {
  set_tag nullify-pending-cidrs "$NULLIFY_EU"
  set_tag nullify-pending-update "update-gone"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  output_has "update-gone of prod is no longer known to EKS"
  [ "$(live_cidrs)" = "$BASE_CIDR $NULLIFY_EU" ]
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs
  no_tag nullify-pending-update
}

@test "remove drops a pending-update tag left with no CIDR record" {
  set_tag nullify-pending-update "update-1"
  run_setup remove
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  no_tag nullify-pending-update
}

@test "apply stops before changing publicAccessCidrs when fewer than three tag slots are free" {
  local i
  for ((i = 1; i <= 48; i++)); do
    set_tag "team-$i" "x"
  done
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  output_has "EKS allows at most 50 per resource"
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
}

@test "apply records CIDRs with exactly three tag slots free" {
  local i
  for ((i = 1; i <= 47; i++)); do
    set_tag "team-$i" "x"
  done
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  [ "$(live_cidrs)" = "$BASE_CIDR $NULLIFY_EU" ]
  [ "$(tag_value nullify-added-cidrs)" = "$NULLIFY_EU" ]
  no_tag nullify-pending-cidrs
  no_tag nullify-pending-update
}

# EKS documents a limit of 50 tags per resource and does not say aws: keys are
# exempt, so the precheck counts them. Excluding them would let this cluster
# pass the precheck and then fail the write with publicAccessCidrs changed.
@test "aws: tags count towards the EKS tag limit" {
  local i
  for ((i = 1; i <= 47; i++)); do
    set_tag "team-$i" "x"
  done
  set_tag "aws:cloudformation:stack-name" "eks"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -ne 0 ]
  output_has "prod has 48 tags"
  not_called 'eks update-cluster-config'
  not_called 'eks tag-resource'
  [ "$(live_cidrs)" = "$BASE_CIDR" ]
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

@test "rejects --authorization admin-view" {
  run_setup apply --nullify-region eu-central-1 --authorization admin-view
  [ "$status" -ne 0 ]
  output_has "admin-view is not supported"
  output_has "Secret values"
  output_has "pods/log"
  output_has "exec"
  not_called 'eks update-cluster-config'
}

@test "apply leaves an existing 0.0.0.0/0 list unchanged, warns, and does not write it" {
  set_cidrs "0.0.0.0/0"
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  not_called 'eks update-cluster-config'
  [ "$(live_cidrs)" = "0.0.0.0/0" ]
  output_has "publicAccessCidrs includes 0.0.0.0/0"
  output_has "verify fails while 0.0.0.0/0 is present"
}

@test "verify fails when publicAccessCidrs contains 0.0.0.0/0" {
  set_cidrs "0.0.0.0/0"
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "publicAccessCidrs contains 0.0.0.0/0"
}

@test "verify fails on 0.0.0.0/0 even when Nullify /32s are also present" {
  set_cidrs "0.0.0.0/0 $NULLIFY_EU"
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "publicAccessCidrs contains 0.0.0.0/0"
}

@test "verify fails when AmazonEKSAdminViewPolicy is associated" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_ADMIN_VIEW_SCOPE=cluster
  export FAKE_ADMIN_VIEW_SCOPE
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "EKS access policies are associated"
  output_has "AmazonEKSAdminViewPolicy"
  output_has "grants get, list and watch on every resource"
}

@test "verify fails when AmazonEKSClusterAdminPolicy is associated" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_ASSOCIATED_POLICIES="arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  export FAKE_ASSOCIATED_POLICIES
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "EKS access policies are associated"
  output_has "AmazonEKSClusterAdminPolicy"
}

@test "verify fails when the access entry has extra Kubernetes groups" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_KUBERNETES_GROUPS="nullify-readonly cluster-admin"
  export FAKE_KUBERNETES_GROUPS
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "extra Kubernetes groups"
  output_has "cluster-admin"
}

@test "verify fails when the group can create pods/attach" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_CAN_I_YES="create pods/attach"
  export FAKE_CAN_I_YES
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "group nullify-readonly can create pods/attach"
}

@test "apply disassociates leftover access policies" {
  FAKE_ADMIN_VIEW_SCOPE=cluster
  export FAKE_ADMIN_VIEW_SCOPE
  run_setup apply --nullify-region eu-central-1
  [ "$status" -eq 0 ]
  called 'eks disassociate-access-policy'
  output_has "disassociating leftover"
}

@test "verify fails when the group can get secrets" {
  set_cidrs "$BASE_CIDR $NULLIFY_EU"
  FAKE_CAN_I_YES="get secrets"
  export FAKE_CAN_I_YES
  run_setup verify --nullify-region eu-central-1 --kube-context test
  [ "$status" -ne 0 ]
  output_has "group nullify-readonly can get secrets"
}

@test "remove disassociates leftover AmazonEKSAdminViewPolicy (cleanup only)" {
  FAKE_ADMIN_VIEW_SCOPE=cluster
  export FAKE_ADMIN_VIEW_SCOPE
  run_setup remove
  [ "$status" -eq 0 ]
  called 'eks disassociate-access-policy'
  output_has "cleanup only"
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
