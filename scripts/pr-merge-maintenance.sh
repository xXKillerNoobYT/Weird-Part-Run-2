#!/usr/bin/env bash
set -euo pipefail
shopt -s nocasematch

usage() {
  cat <<'EOF'
Usage:
  scripts/pr-merge-maintenance.sh [owner/repo]

Environment:
  GH_TOKEN                         Required by gh in GitHub Actions.
  PR_MAINTENANCE_BASE              Base branch to scan. Default: main.
  PR_MAINTENANCE_MAX_PRS           Maximum open PRs to inspect. Default: 50.
  PR_MAINTENANCE_DRY_RUN           Set to 1 to log actions without changing PRs.
  PR_MAINTENANCE_SKIP_LABELS       Comma-separated labels that require manual handling.
  PR_MAINTENANCE_SKIP_TITLE_REGEX  Extended regex for security-sensitive/manual PR titles.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command missing: $cmd" >&2
    exit 1
  fi
done

REPO="${1:-${GITHUB_REPOSITORY:-}}"
BASE="${PR_MAINTENANCE_BASE:-main}"
MAX_PRS="${PR_MAINTENANCE_MAX_PRS:-50}"
DRY_RUN="${PR_MAINTENANCE_DRY_RUN:-0}"
SKIP_LABELS="${PR_MAINTENANCE_SKIP_LABELS:-security,security-sensitive,manual-review,manual-merge,do-not-merge}"
SKIP_TITLE_REGEX="${PR_MAINTENANCE_SKIP_TITLE_REGEX:-security|sqlcipher|encryption|auth|payment|credential|secret|keychain}"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '${REPO:-<empty>}'" >&2
  exit 1
fi
if [[ ! "$MAX_PRS" =~ ^[0-9]+$ || "$MAX_PRS" -lt 1 ]]; then
  echo "error: PR_MAINTENANCE_MAX_PRS must be a positive integer" >&2
  exit 1
fi

IFS=',' read -r -a SKIP_LABEL_ARRAY <<<"$SKIP_LABELS"

has_skip_label() {
  local labels_json="$1"
  local label
  for label in "${SKIP_LABEL_ARRAY[@]}"; do
    label="$(printf "%s" "$label" | xargs)"
    [[ -z "$label" ]] && continue
    if jq -e --arg label "$label" 'map(ascii_downcase) | index($label | ascii_downcase)' <<<"$labels_json" >/dev/null; then
      return 0
    fi
  done
  return 1
}

run_or_log() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

echo "Scanning up to $MAX_PRS open PRs in $REPO targeting $BASE"

prs_json="$(gh pr list \
  --repo "$REPO" \
  --base "$BASE" \
  --state open \
  --limit "$MAX_PRS" \
  --json number,title,isDraft,labels,headRepositoryOwner,mergeStateStatus,mergeable,autoMergeRequest)"

if [[ "$(jq 'length' <<<"$prs_json")" -eq 0 ]]; then
  echo "No open PRs targeting $BASE."
  exit 0
fi

while IFS= read -r pr; do
  number="$(jq -r '.number' <<<"$pr")"
  title="$(jq -r '.title' <<<"$pr")"
  is_draft="$(jq -r '.isDraft' <<<"$pr")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr")"
  mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr")"
  auto_merge_enabled="$(jq -r '.autoMergeRequest != null' <<<"$pr")"
  labels_json="$(jq -c '[.labels[]?.name]' <<<"$pr")"
  head_owner="$(jq -r '.headRepositoryOwner.login // ""' <<<"$pr")"
  repo_owner="${REPO%%/*}"

  echo "::group::PR #$number"
  echo "title=$title"
  echo "mergeStateStatus=$merge_state mergeable=$mergeable autoMerge=$auto_merge_enabled draft=$is_draft headOwner=$head_owner"
  blocked=0

  if [[ "$is_draft" == "true" ]]; then
    echo "skip: draft PR"
    echo "::endgroup::"
    continue
  fi

  if [[ "$head_owner" != "$repo_owner" ]]; then
    echo "skip: fork PRs require manual handling"
    echo "::endgroup::"
    continue
  fi

  if has_skip_label "$labels_json" || [[ "$title" =~ $SKIP_TITLE_REGEX ]]; then
    echo "skip: security-sensitive or manual-review PR"
    echo "::endgroup::"
    continue
  fi

  if [[ "$mergeable" == "CONFLICTING" ]]; then
    echo "blocked: PR has merge conflicts; route to an engineer instead of forcing merge"
    echo "::endgroup::"
    continue
  fi

  case "$merge_state" in
    DIRTY)
      echo "blocked: PR has merge conflicts; route to an engineer instead of forcing merge"
      blocked=1
      ;;
    BEHIND|UNKNOWN)
      echo "updating branch from $BASE"
      if ! run_or_log gh pr update-branch "$number" --repo "$REPO"; then
        echo "blocked: branch update failed; route to an engineer"
        blocked=1
      fi
      ;;
    CLEAN|HAS_HOOKS|UNSTABLE|BLOCKED)
      echo "branch state can proceed through branch protection/auto-merge"
      ;;
    *)
      echo "blocked: unhandled merge state '$merge_state'; skipping to be conservative"
      blocked=1
      ;;
  esac

  if [[ "$auto_merge_enabled" != "true" && "$blocked" != "1" ]]; then
    echo "enabling squash auto-merge"
    if ! run_or_log gh pr merge "$number" --repo "$REPO" --auto --squash --delete-branch; then
      echo "blocked: auto-merge enable failed"
    fi
  fi

  echo "::endgroup::"
done < <(jq -c '.[]' <<<"$prs_json")
