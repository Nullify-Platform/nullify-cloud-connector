#!/usr/bin/env bash
# Pure helpers for managing Nullify egress CIDRs in an EKS cluster's
# publicAccessCidrs. Sourced by setup-eks-managed-scan.sh and
# tests/cidr-merge.bats. No AWS calls. Lists are space-separated strings.
# Works under bash 3.2 (macOS) and in callers running `set -euo pipefail`.

EKS_MAX_PUBLIC_ACCESS_CIDRS=40
OPEN_CIDR="0.0.0.0/0"

# nullify_egress_cidrs NULLIFY_REGION
# Prints Nullify's egress IPs for a Nullify region as /32 CIDRs.
# Hardcoded until GET /context/cloud-integration/egress-ips publishes them.
nullify_egress_cidrs() {
  case "${1:-}" in
    ap-southeast-2) echo "13.55.32.104/32 3.105.146.106/32 13.211.99.100/32" ;;
    eu-central-1) echo "18.198.60.231/32 18.157.227.250/32 18.185.152.197/32" ;;
    us-east-2) echo "52.15.146.50/32 16.58.40.80/32 3.133.15.210/32" ;;
    *)
      echo "unknown Nullify region '${1:-}' (known: ap-southeast-2, eu-central-1, us-east-2)" >&2
      return 1
      ;;
  esac
}

# cidr_normalise LIST
# Prints LIST with tabs, newlines and repeated spaces collapsed to single spaces.
cidr_normalise() {
  local -a words
  read -r -a words <<< "$(printf '%s' "${1:-}" | tr '\t\n' '  ')"
  echo "${words[*]:-}"
}

# cidr_is_ipv4 CIDR
# Succeeds when CIDR is an IPv4 address with a prefix length, e.g. 203.0.113.7/32.
cidr_is_ipv4() {
  local cidr="${1:-}" octet
  local -a octets
  if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    return 1
  fi
  if (( 10#${cidr#*/} > 32 )); then
    return 1
  fi
  IFS=. read -r -a octets <<< "${cidr%/*}"
  for octet in "${octets[@]}"; do
    if (( 10#$octet > 255 )); then
      return 1
    fi
  done
  return 0
}

# cidr_list_contains NEEDLE [ITEM...]
cidr_list_contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

# cidr_merge CURRENT ADDITIONS
# Prints the publicAccessCidrs list after adding ADDITIONS to CURRENT: CURRENT
# order kept, new entries appended, duplicates dropped. A CURRENT list holding
# 0.0.0.0/0 already admits every IPv4 address, so it is printed unchanged and
# never narrowed.
# Returns 2 when an addition is not an IPv4 CIDR, and 3 when the result would
# exceed the EKS limit of 40 public access CIDRs.
cidr_merge() {
  local cidr
  local -a current additions merged
  read -r -a current <<< "$(cidr_normalise "${1:-}")"
  read -r -a additions <<< "$(cidr_normalise "${2:-}")"
  merged=()
  for cidr in ${additions[@]+"${additions[@]}"}; do
    if ! cidr_is_ipv4 "$cidr"; then
      echo "not an IPv4 CIDR: $cidr" >&2
      return 2
    fi
  done
  if cidr_list_contains "$OPEN_CIDR" ${current[@]+"${current[@]}"}; then
    echo "${current[*]}"
    return 0
  fi
  for cidr in ${current[@]+"${current[@]}"} ${additions[@]+"${additions[@]}"}; do
    if ! cidr_list_contains "$cidr" ${merged[@]+"${merged[@]}"}; then
      merged+=("$cidr")
    fi
  done
  if (( ${#merged[@]} > EKS_MAX_PUBLIC_ACCESS_CIDRS )); then
    echo "result has ${#merged[@]} CIDRs; EKS allows at most ${EKS_MAX_PUBLIC_ACCESS_CIDRS}" >&2
    return 3
  fi
  echo "${merged[*]:-}"
}

# cidr_missing CURRENT REQUIRED
# Prints the REQUIRED entries that CURRENT does not admit. A CURRENT list
# holding 0.0.0.0/0 admits everything.
cidr_missing() {
  local cidr
  local -a current required missing
  read -r -a current <<< "$(cidr_normalise "${1:-}")"
  read -r -a required <<< "$(cidr_normalise "${2:-}")"
  missing=()
  if cidr_list_contains "$OPEN_CIDR" ${current[@]+"${current[@]}"}; then
    echo ""
    return 0
  fi
  for cidr in ${required[@]+"${required[@]}"}; do
    if ! cidr_list_contains "$cidr" ${current[@]+"${current[@]}"}; then
      missing+=("$cidr")
    fi
  done
  echo "${missing[*]:-}"
}

# cidr_union A B
# Prints A followed by the entries of B that are not already in A.
cidr_union() {
  local cidr
  local -a result extra
  read -r -a result <<< "$(cidr_normalise "${1:-}")"
  read -r -a extra <<< "$(cidr_normalise "${2:-}")"
  for cidr in ${extra[@]+"${extra[@]}"}; do
    if ! cidr_list_contains "$cidr" ${result[@]+"${result[@]}"}; then
      result+=("$cidr")
    fi
  done
  echo "${result[*]:-}"
}

# cidr_intersect A B
# Prints the entries of A that are literally present in B, in A's order.
cidr_intersect() {
  local cidr
  local -a first second result
  read -r -a first <<< "$(cidr_normalise "${1:-}")"
  read -r -a second <<< "$(cidr_normalise "${2:-}")"
  result=()
  for cidr in ${first[@]+"${first[@]}"}; do
    if cidr_list_contains "$cidr" ${second[@]+"${second[@]}"}; then
      result+=("$cidr")
    fi
  done
  echo "${result[*]:-}"
}

# cidr_difference A B
# Prints the entries of A that are not literally present in B, in A's order.
# Unlike cidr_remove, an empty result is allowed.
cidr_difference() {
  local cidr
  local -a first second result
  read -r -a first <<< "$(cidr_normalise "${1:-}")"
  read -r -a second <<< "$(cidr_normalise "${2:-}")"
  result=()
  for cidr in ${first[@]+"${first[@]}"}; do
    if ! cidr_list_contains "$cidr" ${second[@]+"${second[@]}"}; then
      result+=("$cidr")
    fi
  done
  echo "${result[*]:-}"
}

# cidr_tag_is_part BASE KEY
# Succeeds when KEY is BASE or a numbered continuation of it (BASE-2, BASE-3, ...).
cidr_tag_is_part() {
  local base="${1:-}" key="${2:-}" suffix part_number='^([2-9]|[1-9][0-9]+)$'
  if [[ -z "$base" ]]; then
    return 1
  fi
  if [[ "$key" == "$base" ]]; then
    return 0
  fi
  suffix="${key#"$base"-}"
  [[ "$suffix" != "$key" && "$suffix" =~ $part_number ]]
}

# cidr_tag_part_key BASE INDEX
# Prints the tag key holding chunk INDEX (1-based) of a list stored under BASE:
# BASE for the first chunk, BASE-INDEX for the rest.
cidr_tag_part_key() {
  if (( ${2:-1} <= 1 )); then
    echo "$1"
  else
    echo "$1-$2"
  fi
}

# cidr_tag_chunks LIST MAX_LENGTH
# Prints LIST as space-separated chunks of at most MAX_LENGTH characters, one
# chunk per line and no CIDR split across chunks, so a list longer than one EKS
# tag value (256 characters) can be stored as BASE, BASE-2, ... Prints nothing
# for an empty list. Returns 5 when a single entry is longer than MAX_LENGTH.
cidr_tag_chunks() {
  local max="${2:-256}" cidr chunk=""
  local -a items
  read -r -a items <<< "$(cidr_normalise "${1:-}")"
  for cidr in ${items[@]+"${items[@]}"}; do
    if (( ${#cidr} > max )); then
      echo "entry longer than $max characters: $cidr" >&2
      return 5
    fi
    if [[ -z "$chunk" ]]; then
      chunk="$cidr"
    elif (( ${#chunk} + 1 + ${#cidr} <= max )); then
      chunk="$chunk $cidr"
    else
      echo "$chunk"
      chunk="$cidr"
    fi
  done
  if [[ -n "$chunk" ]]; then
    echo "$chunk"
  fi
}

# cidr_remove CURRENT RECORDED
# Prints CURRENT without the entries in RECORDED (the CIDRs this tooling added).
# Returns 4, printing nothing on stdout, when the result would be empty: an
# empty publicAccessCidrs list cannot express a closed endpoint, and falling
# back to 0.0.0.0/0 would open it to everyone.
cidr_remove() {
  local cidr
  local -a current recorded remaining
  read -r -a current <<< "$(cidr_normalise "${1:-}")"
  read -r -a recorded <<< "$(cidr_normalise "${2:-}")"
  remaining=()
  for cidr in ${current[@]+"${current[@]}"}; do
    if ! cidr_list_contains "$cidr" ${recorded[@]+"${recorded[@]}"}; then
      remaining+=("$cidr")
    fi
  done
  if (( ${#remaining[@]} == 0 )); then
    echo "removing '${2:-}' would leave publicAccessCidrs empty" >&2
    return 4
  fi
  echo "${remaining[*]}"
}

# cidr_json_array LIST
# Prints LIST as a JSON array of strings. Entries are CIDRs, which need no
# JSON escaping.
cidr_json_array() {
  local cidr sep="" out="["
  local -a items
  read -r -a items <<< "$(cidr_normalise "${1:-}")"
  for cidr in ${items[@]+"${items[@]}"}; do
    out="${out}${sep}\"${cidr}\""
    sep=","
  done
  echo "${out}]"
}
