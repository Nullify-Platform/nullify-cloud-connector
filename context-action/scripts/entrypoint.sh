#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Nullify Context Action — Entrypoint
# Determines what action to take based on GitHub event context
# and mode, then invokes the Nullify CLI.
# ============================================================

ACTION_TAKEN="skipped"

# --- Detect event context ---
EVENT_NAME="${GITHUB_EVENT_NAME:-}"
REF_NAME="${GITHUB_REF_NAME:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"
SHA="${GITHUB_SHA:-}"
PR_NUMBER=""
PR_MERGED="false"
PR_DRAFT="false"

if [[ "$EVENT_NAME" == "pull_request" ]]; then
  PR_NUMBER=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
  PR_MERGED=$(jq -r '.pull_request.merged // false' "$GITHUB_EVENT_PATH")
  PR_DRAFT=$(jq -r '.pull_request.draft // false' "$GITHUB_EVENT_PATH")
  PR_ACTION=$(jq -r '.action // empty' "$GITHUB_EVENT_PATH")
fi

echo "Event: $EVENT_NAME | Mode: $INPUT_MODE | Ref: $REF_NAME | PR: ${PR_NUMBER:-none}"

# --- Skip on draft PRs ---
if [[ "$INPUT_SKIP_ON_DRAFT" == "true" && "$PR_DRAFT" == "true" ]]; then
  echo "Skipping — draft PR"
  echo "action_taken=skipped" >> "$GITHUB_OUTPUT"
  exit 0
fi

# --- Mode decision matrix ---
should_upload="false"
should_cleanup="false"

case "$INPUT_MODE" in
  merge-only)
    if [[ "$EVENT_NAME" == "push" ]]; then
      should_upload="true"
    fi
    ;;
  pr-only)
    if [[ "$EVENT_NAME" == "pull_request" ]]; then
      if [[ "$PR_ACTION" == "closed" ]]; then
        should_cleanup="true"
      elif [[ "$PR_ACTION" == "opened" || "$PR_ACTION" == "synchronize" ]]; then
        should_upload="true"
      fi
    fi
    ;;
  both)
    if [[ "$EVENT_NAME" == "push" ]]; then
      should_upload="true"
    elif [[ "$EVENT_NAME" == "pull_request" ]]; then
      if [[ "$PR_ACTION" == "closed" && "$PR_MERGED" == "true" ]]; then
        # Merged — the push event handles the upload
        should_cleanup="true"
      elif [[ "$PR_ACTION" == "closed" && "$PR_MERGED" != "true" ]]; then
        should_cleanup="true"
      elif [[ "$PR_ACTION" == "opened" || "$PR_ACTION" == "synchronize" ]]; then
        should_upload="true"
      fi
    fi
    ;;
  *)
    echo "::error::Invalid mode: $INPUT_MODE (must be merge-only, pr-only, or both)"
    exit 1
    ;;
esac

# --- Execute ---
if [[ "$should_upload" == "true" ]]; then
  # Build CLI args
  CLI_ARGS="--type $INPUT_TYPE --name $INPUT_NAME"

  if [[ -n "$INPUT_ENVIRONMENT" ]]; then
    CLI_ARGS="$CLI_ARGS --environment $INPUT_ENVIRONMENT"
  fi

  if [[ -n "$PR_NUMBER" && "$EVENT_NAME" == "pull_request" ]]; then
    CLI_ARGS="$CLI_ARGS --pr-number $PR_NUMBER"
  fi

  if [[ "$INPUT_DRY_RUN" == "true" ]]; then
    CLI_ARGS="$CLI_ARGS --dry-run"
  fi

  # Resolve files to upload
  FILES=""
  if [[ -n "$INPUT_PLAN_PATH" ]]; then
    # Use glob expansion
    shopt -s nullglob globstar
    for f in $INPUT_PLAN_PATH; do
      FILES="$FILES $f"
    done
    shopt -u nullglob globstar
  fi

  if [[ -z "$FILES" && -n "$INPUT_PLAN_PATH" ]]; then
    echo "::warning::No files matched pattern: $INPUT_PLAN_PATH"
    echo "action_taken=skipped" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  echo "Uploading context: type=$INPUT_TYPE name=$INPUT_NAME"
  # shellcheck disable=SC2086
  nullify api context push $CLI_ARGS $FILES

  ACTION_TAKEN="uploaded"

elif [[ "$should_cleanup" == "true" ]]; then
  echo "PR #${PR_NUMBER} closed — cleanup would happen here (not yet implemented)"
  ACTION_TAKEN="cleaned-up"

else
  echo "No action needed for event=$EVENT_NAME mode=$INPUT_MODE"
fi

echo "action_taken=$ACTION_TAKEN" >> "$GITHUB_OUTPUT"
