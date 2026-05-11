#!/usr/bin/env bash
set -euo pipefail

# gh-issue-close-guard.sh — Pre-close heuristic guard for GitHub issues.
#
# Before any agent auto-closes a GitHub issue, this script checks three
# conditions that indicate the issue is still actively tracked. If any
# check triggers, the script exits non-zero and prints the reason.
#
# Usage:
#   scripts/gh-issue-close-guard.sh <issue-number> [repo-root]
#
# Exit codes:
#   0  — Safe to close (no active references found)
#   1  — DO NOT CLOSE (active reference found; reason printed to stdout)
#   2  — Usage/argument error
#
# References: GitHub #233, Paperclip WEI-409

usage() {
  cat <<'EOF'
Usage:
  scripts/gh-issue-close-guard.sh <issue-number> [repo-root]

Checks whether a GitHub issue is safe to auto-close by scanning for
active references in dev-qa.md, plan files, and the Xcode prompt queue.

Exit 0 = safe to close. Exit 1 = DO NOT CLOSE (reason printed).
EOF
}

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 2
fi

ISSUE_NUM="$1"
REPO_ROOT="${2:-.}"

if [[ ! "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
  echo "error: issue number must be numeric, got '$ISSUE_NUM'" >&2
  exit 2
fi

BLOCKED=0
REASONS=()

# ---------------------------------------------------------------------------
# Check 1: Is the issue referenced in docs/dev-qa.md Pending Questions?
# ---------------------------------------------------------------------------
DEV_QA="$REPO_ROOT/docs/dev-qa.md"
if [[ -f "$DEV_QA" ]]; then
  # Extract the Pending Questions section (between "## Pending Questions" and
  # the next "---" or "##" heading). Exclude HTML-commented archived clusters.
  # Then search for the issue number as #NNN or issue NNN.
  pending_section=$(
    awk '
      /^## Pending Questions/    { capture=1; next }
      capture && /^(---|## )/    { capture=0 }
      capture && !/^<!--/        { print }
    ' "$DEV_QA"
  )

  if echo "$pending_section" | grep -qE "(#${ISSUE_NUM}([^0-9]|$)|issue ${ISSUE_NUM}([^0-9]|$))" 2>/dev/null; then
    BLOCKED=1
    REASONS+=("dev-qa.md: issue #${ISSUE_NUM} is referenced in the Pending Questions section")
  fi
fi

# ---------------------------------------------------------------------------
# Check 2: Is the issue referenced in a docs/plans/*.md file alongside a
#           pending-status marker?
# ---------------------------------------------------------------------------
PLANS_DIR="$REPO_ROOT/docs/plans"
if [[ -d "$PLANS_DIR" ]]; then
  # Markers that indicate the plan work is not yet done
  PENDING_MARKERS="(not yet implemented|implementation pending|pending|in.progress|phase.*pending|status:.*todo|status:.*blocked|status:.*queued)"

  while IFS= read -r plan_file; do
    # Check if this plan file references the issue number
    if grep -qE "(#${ISSUE_NUM}([^0-9]|$)|issue ${ISSUE_NUM}([^0-9]|$)|GH#${ISSUE_NUM}([^0-9]|$))" "$plan_file" 2>/dev/null; then
      # Check if the same file has a pending status marker
      if grep -qiE "$PENDING_MARKERS" "$plan_file" 2>/dev/null; then
        rel_path="${plan_file#"$REPO_ROOT"/}"
        BLOCKED=1
        REASONS+=("plan file: issue #${ISSUE_NUM} is referenced in ${rel_path} which contains pending-status markers")
        break  # One match is enough to block
      fi
    fi
  done < <(find "$PLANS_DIR" -name '*.md' -type f 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# Check 3: Is the issue referenced in xcode-ai/fix-prompts/00-fix-order.md
#           as a non-DONE item?
# ---------------------------------------------------------------------------
FIX_ORDER="$REPO_ROOT/xcode-ai/fix-prompts/00-fix-order.md"
if [[ -f "$FIX_ORDER" ]]; then
  # Look for lines referencing the issue that are NOT marked DONE
  while IFS= read -r line; do
    # Skip lines that are marked as done
    if echo "$line" | grep -qiE "(DONE|done|archived|closed)" 2>/dev/null; then
      continue
    fi
    # If we find the issue number on a non-done line, block
    BLOCKED=1
    REASONS+=("fix-order: issue #${ISSUE_NUM} is queued in 00-fix-order.md (not yet DONE)")
    break
  done < <(grep -E "(#${ISSUE_NUM}([^0-9]|$)|GitHub #${ISSUE_NUM}([^0-9]|$))" "$FIX_ORDER" 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "$BLOCKED" -eq 1 ]]; then
  echo "BLOCK: issue #${ISSUE_NUM} must NOT be auto-closed."
  for reason in "${REASONS[@]}"; do
    echo "  - $reason"
  done
  exit 1
else
  echo "OK: issue #${ISSUE_NUM} has no active references — safe to close."
  exit 0
fi
