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

@test "intersect keeps only entries present in both, in the first list's order" {
  run cidr_intersect "18.157.227.250/32 198.51.100.7/32 18.198.60.231/32" "203.0.113.0/24 18.198.60.231/32 18.157.227.250/32"
  [ "$status" -eq 0 ]
  [ "$output" = "18.157.227.250/32 18.198.60.231/32" ]
}

@test "intersect is literal: 0.0.0.0/0 does not contain a /32" {
  run cidr_intersect "18.198.60.231/32" "0.0.0.0/0"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "difference drops entries present in the second list and may be empty" {
  run cidr_difference "18.198.60.231/32 198.51.100.7/32" "18.198.60.231/32"
  [ "$status" -eq 0 ]
  [ "$output" = "198.51.100.7/32" ]
  run cidr_difference "18.198.60.231/32" "18.198.60.231/32"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tag part matches the base key and numbered continuations only" {
  local key
  for key in nullify-added-cidrs nullify-added-cidrs-2 nullify-added-cidrs-10; do
    run cidr_tag_is_part nullify-added-cidrs "$key"
    [ "$status" -eq 0 ]
  done
  for key in nullify-added-cidrs-1 nullify-added-cidrs-0 nullify-added-cidrs-x nullify-added-cidrsx nullify-pending-cidrs Name; do
    run cidr_tag_is_part nullify-added-cidrs "$key"
    [ "$status" -ne 0 ]
  done
}

@test "tag part key is the base for the first chunk and numbered after it" {
  run cidr_tag_part_key nullify-added-cidrs 1
  [ "$output" = "nullify-added-cidrs" ]
  run cidr_tag_part_key nullify-added-cidrs 2
  [ "$output" = "nullify-added-cidrs-2" ]
  run cidr_tag_is_part nullify-added-cidrs "$(cidr_tag_part_key nullify-added-cidrs 12)"
  [ "$status" -eq 0 ]
}

@test "tag chunks keep a short list in one chunk" {
  run cidr_tag_chunks "$NULLIFY_EU" 256
  [ "$status" -eq 0 ]
  [ "$output" = "$NULLIFY_EU" ]
}

@test "tag chunks split a long list without splitting a CIDR or exceeding the limit" {
  local list="" i line joined=""
  for ((i = 100; i < 140; i++)); do
    list="${list:+$list }203.0.${i}.255/32"
  done
  run cidr_tag_chunks "$list" 256
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 1 ]
  for line in "${lines[@]}"; do
    [ "${#line}" -le 256 ]
    joined="${joined:+$joined }$line"
  done
  [ "$joined" = "$list" ]
}

@test "tag chunks of an empty list print nothing" {
  run cidr_tag_chunks "" 256
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
