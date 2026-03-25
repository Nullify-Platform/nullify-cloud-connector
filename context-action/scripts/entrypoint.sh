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
PR_NUMBER=""
PR_MERGED="false"
PR_DRAFT="false"
PR_ACTION=""

if [[ "$EVENT_NAME" == "pull_request" ]]; then
  PR_NUMBER=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
  PR_MERGED=$(jq -r '.pull_request.merged // false' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "false")
  PR_DRAFT=$(jq -r '.pull_request.draft // false' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "false")
  PR_ACTION=$(jq -r '.action // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
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
      if [[ "$PR_ACTION" == "closed" ]]; then
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
  # Resolve files to upload
  PLAN_PATH="${INPUT_PLAN_PATH:-}"
  if [[ -z "$PLAN_PATH" ]]; then
    # Default: find all plan.json files recursively
    PLAN_PATH="**/plan.json"
  fi

  # Expand glob into array safely
  shopt -s nullglob globstar
  FILES=()
  for f in $PLAN_PATH; do
    FILES+=("$f")
  done
  shopt -u nullglob globstar

  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "::warning::No files matched pattern: $PLAN_PATH"
    echo "action_taken=skipped" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  echo "Found ${#FILES[@]} file(s) to upload"

  # Upload each file as a separate context entry with name derived from path
  for f in "${FILES[@]}"; do
    # Derive name from file's parent directory
    # e.g. infrastructure/networking/plan.json → infrastructure/networking
    # e.g. plan.json → root
    FILE_DIR=$(dirname "$f")
    if [[ "$FILE_DIR" == "." || "$FILE_DIR" == "/" ]]; then
      FILE_NAME="root"
    else
      FILE_NAME="$FILE_DIR"
    fi

    # Use explicit --name if provided, otherwise use derived name
    EFFECTIVE_NAME="${INPUT_NAME:-$FILE_NAME}"

    # Build CLI args as array (prevents command injection)
    CLI_ARGS=(
      "--type" "$INPUT_TYPE"
      "--name" "$EFFECTIVE_NAME"
    )

    if [[ -n "${INPUT_ENVIRONMENT:-}" ]]; then
      CLI_ARGS+=("--environment" "$INPUT_ENVIRONMENT")
    fi

    if [[ -n "$PR_NUMBER" && "$EVENT_NAME" == "pull_request" ]]; then
      CLI_ARGS+=("--pr-number" "$PR_NUMBER")
    fi

    if [[ "${INPUT_DRY_RUN:-false}" == "true" ]]; then
      CLI_ARGS+=("--dry-run")
    fi

    echo "Uploading: $f (name=$EFFECTIVE_NAME)"
    nullify api context push "${CLI_ARGS[@]}" "$f"
  done

  ACTION_TAKEN="uploaded"

elif [[ "$should_cleanup" == "true" ]]; then
  echo "PR #${PR_NUMBER} closed — cleanup would happen here (not yet implemented)"
  ACTION_TAKEN="cleaned-up"

else
  echo "No action needed for event=$EVENT_NAME mode=$INPUT_MODE"
fi

echo "action_taken=$ACTION_TAKEN" >> "$GITHUB_OUTPUT"
