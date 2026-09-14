#!/usr/bin/env bats
# Unit tests for aws-integration-setup/scripts/lib/cidr-merge.sh.
# Run from the repository root: bats aws-integration-setup/scripts/tests

setup() {
  # shellcheck source=../lib/cidr-merge.sh
  source "${BATS_TEST_DIRNAME}/../lib/cidr-merge.sh"
  NULLIFY_EU="18.198.60.231/32 18.157.227.250/32 18.185.152.197/32"
}

cidr_block() {
  local count="$1" i out=""
  for ((i = 1; i <= count; i++)); do
    out="${out:+$out }10.0.${i}.0/24"
  done
  echo "$out"
}

word_count() {
  local -a words
  read -r -a words <<< "$1"
  echo "${#words[@]}"
}

@test "merge appends Nullify CIDRs to a restricted list" {
  run cidr_merge "203.0.113.0/24" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "203.0.113.0/24 18.198.60.231/32 18.157.227.250/32 18.185.152.197/32" ]
}

@test "merge keeps a CIDR that is already present only once" {
  run cidr_merge "18.198.60.231/32 203.0.113.0/24" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "18.198.60.231/32 203.0.113.0/24 18.157.227.250/32 18.185.152.197/32" ]
}

@test "merge leaves a complete list unchanged" {
  run cidr_merge "$NULLIFY_EU" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "$NULLIFY_EU" ]
}

@test "merge never narrows a list containing 0.0.0.0/0" {
  run cidr_merge "0.0.0.0/0" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "0.0.0.0/0" ]
}

@test "merge accepts tab-separated aws text output" {
  run cidr_merge $'203.0.113.0/24\t198.51.100.0/24' "18.198.60.231/32"
  [ "$status" -eq 0 ]
  [ "$output" = "203.0.113.0/24 198.51.100.0/24 18.198.60.231/32" ]
}

@test "merge into an empty list returns the additions" {
  run cidr_merge "" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "$NULLIFY_EU" ]
}

@test "merge allows exactly 40 CIDRs" {
  run cidr_merge "$(cidr_block 37)" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$(word_count "$output")" -eq 40 ]
}

@test "merge refuses more than 40 CIDRs" {
  run cidr_merge "$(cidr_block 38)" "$NULLIFY_EU"
  [ "$status" -eq 3 ]
}

@test "merge rejects an address without a prefix length" {
  run cidr_merge "203.0.113.0/24" "18.198.60.231"
  [ "$status" -eq 2 ]
}

@test "merge rejects an out-of-range octet" {
  run cidr_merge "203.0.113.0/24" "300.1.1.1/32"
  [ "$status" -eq 2 ]
}

@test "merge rejects a prefix longer than 32" {
  run cidr_merge "203.0.113.0/24" "10.0.0.0/33"
  [ "$status" -eq 2 ]
}

@test "missing lists required CIDRs that are not present" {
  run cidr_missing "18.198.60.231/32 203.0.113.0/24" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ "$output" = "18.157.227.250/32 18.185.152.197/32" ]
}

@test "missing is empty when 0.0.0.0/0 is present" {
  run cidr_missing "0.0.0.0/0" "$NULLIFY_EU"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove drops only the recorded CIDRs" {
  run cidr_remove "203.0.113.0/24 18.198.60.231/32 198.51.100.7/32" "18.198.60.231/32 18.157.227.250/32"
  [ "$status" -eq 0 ]
  [ "$output" = "203.0.113.0/24 198.51.100.7/32" ]
}

@test "remove refuses to leave the list empty" {
  run cidr_remove "$NULLIFY_EU" "$NULLIFY_EU"
  [ "$status" -eq 4 ]
}

@test "union appends new entries once" {
  run cidr_union "18.198.60.231/32" "18.198.60.231/32 18.157.227.250/32"
  [ "$status" -eq 0 ]
  [ "$output" = "18.198.60.231/32 18.157.227.250/32" ]
}

@test "union of an empty record is the new entries" {
  run cidr_union "" "18.157.227.250/32"
  [ "$status" -eq 0 ]
  [ "$output" = "18.157.227.250/32" ]
}

@test "json array renders a list" {
  run cidr_json_array "18.198.60.231/32 203.0.113.0/24"
  [ "$status" -eq 0 ]
  [ "$output" = '["18.198.60.231/32","203.0.113.0/24"]' ]
}

@test "json array renders an empty list" {
  run cidr_json_array ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "egress table has three valid /32s per Nullify region" {
  local region cidr
  for region in ap-southeast-2 eu-central-1 us-east-2; do
    run nullify_egress_cidrs "$region"
    [ "$status" -eq 0 ]
    [ "$(word_count "$output")" -eq 3 ]
    for cidr in $output; do
      cidr_is_ipv4 "$cidr"
      [ "${cidr#*/}" = "32" ]
    done
  done
}

@test "egress table rejects an unknown Nullify region" {
  run nullify_egress_cidrs "us-west-1"
  [ "$status" -eq 1 ]
}
