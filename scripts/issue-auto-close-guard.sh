#!/usr/bin/env bash
# issue-auto-close-guard.sh — Pre-close heuristic guard for GitHub issues.
#
# Before any scanner agent closes a GitHub issue, run this guard.
# It implements three checks that detect "actively tracked" state:
#
#   Check A — Issue number found in the Pending Questions section of
#             docs/dev-qa.md (not inside an HTML comment / archived block).
#
#   Check B — Issue number appears in any docs/plans/*.md file alongside
#             a "pending / not yet implemented / phase N pending" status
#             marker within a 5-line window.
#
#   Check C — Issue number appears in a QUEUED (🔲 / "to be written") row
#             of xcode-ai/fix-prompts/00-fix-order.md Queue table.
#
# Usage:
#   scripts/issue-auto-close-guard.sh <issue-number> [repo-root]
#
# Arguments:
#   issue-number   GitHub issue number (integer, e.g. 221)
#   repo-root      Optional path to repo root. Defaults to the directory
#                  two levels above this script (i.e. the repo root when
#                  the script lives at <root>/scripts/).
#
# Exit codes:
#   0  — SAFE TO CLOSE — no active-tracking references found.
#   1  — SKIP AUTO-CLOSE — at least one active reference found.
#        Reasons are printed to stdout (one line per triggered check).
#   2  — Usage / environment error.
#
# Example:
#   if ! scripts/issue-auto-close-guard.sh 221; then
#     echo "Issue #221 is actively tracked — skipping auto-close."
#   fi

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: scripts/issue-auto-close-guard.sh <issue-number> [repo-root]

  issue-number  GitHub issue number (positive integer)
  repo-root     Path to repository root (default: two levels above this script)

Exit codes:
  0  SAFE TO CLOSE
  1  SKIP AUTO-CLOSE (active reference found — reason printed to stdout)
  2  Usage / environment error
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "error: issue-number is required" >&2
  usage >&2
  exit 2
fi

ISSUE_NUM="${1}"
if [[ ! "$ISSUE_NUM" =~ ^[0-9]+$ || "$ISSUE_NUM" -lt 1 ]]; then
  echo "error: issue-number must be a positive integer, got '$ISSUE_NUM'" >&2
  exit 2
fi

# Resolve repo root: caller-supplied arg > two levels up from script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${2:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "error: repo-root does not exist: $REPO_ROOT" >&2
  exit 2
fi

DEV_QA_FILE="$REPO_ROOT/docs/dev-qa.md"
PLANS_DIR="$REPO_ROOT/docs/plans"
XCODE_QUEUE_FILE="$REPO_ROOT/xcode-ai/fix-prompts/00-fix-order.md"

SKIP=0    # set to 1 if any check triggers
REASONS=()

# ---------------------------------------------------------------------------
# Helper: escape issue number for use in grep patterns
# ---------------------------------------------------------------------------
# Matches: #221  GitHub #221  #221.  (#221)  etc.
issue_pattern() {
  printf '#%s' "$ISSUE_NUM"
}

# ---------------------------------------------------------------------------
# Check A — docs/dev-qa.md Pending Questions section
# ---------------------------------------------------------------------------
# Strategy: extract the text between "## Pending Questions" and the first
# subsequent "## " heading (Answered Clusters, etc.) or an HTML comment
# block start (<!--), then grep for the issue number.
#
# This avoids false-positives from archived / answered clusters.

check_a_dev_qa() {
  [[ -f "$DEV_QA_FILE" ]] || return 0

  local in_pending=0
  local pending_text=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ Pending\ Questions ]]; then
      in_pending=1
      continue
    fi
    # Stop at the next ## heading (Answered Clusters) or an HTML comment
    # archival block.
    if [[ $in_pending -eq 1 ]]; then
      if [[ "$line" =~ ^##\  ]] || [[ "$line" =~ ^\<\!-- ]]; then
        break
      fi
      pending_text+="$line"$'\n'
    fi
  done < "$DEV_QA_FILE"

  if [[ -z "$pending_text" ]]; then
    return 0
  fi

  # Check for "None" sentinel — section explicitly empty
  if echo "$pending_text" | grep -qiE '^\s*_[Nn]one'; then
    return 0
  fi

  local pat
  pat="$(issue_pattern)"
  if echo "$pending_text" | grep -qF "$pat"; then
    SKIP=1
    REASONS+=("Check A: #${ISSUE_NUM} found in Pending Questions section of docs/dev-qa.md — issue is still awaiting owner answer")
  fi
}

# ---------------------------------------------------------------------------
# Check B — docs/plans/*.md with pending status markers
# ---------------------------------------------------------------------------
# For each plan file that mentions #<N>, inspect up to 5 lines of context
# around each match for a "pending / not yet implemented / phase pending"
# marker (case-insensitive).

PENDING_MARKERS='pending|not yet implemented|implementation pending|phase [0-9a-z]+ pending|status:.*pending|in progress|not done|todo'

check_b_plans() {
  [[ -d "$PLANS_DIR" ]] || return 0

  local pat
  pat="$(issue_pattern)"

  local found_files=()

  while IFS= read -r -d '' plan_file; do
    # Does the file mention this issue?
    grep -qF "$pat" "$plan_file" 2>/dev/null || continue

    # Extract a 5-line context window around each match and look for markers.
    local ctx
    ctx="$(grep -i -F "$pat" -A 5 -B 5 "$plan_file" 2>/dev/null || true)"
    if echo "$ctx" | grep -qiE "$PENDING_MARKERS"; then
      found_files+=("$plan_file")
    fi
  done < <(find "$PLANS_DIR" -maxdepth 1 -name '*.md' -print0 2>/dev/null)

  if [[ ${#found_files[@]} -gt 0 ]]; then
    local rel_paths=()
    for f in "${found_files[@]}"; do
      rel_paths+=("${f#"$REPO_ROOT/"}")
    done
    SKIP=1
    REASONS+=("Check B: #${ISSUE_NUM} found alongside a pending-status marker in: ${rel_paths[*]}")
  fi
}

# ---------------------------------------------------------------------------
# Check C — xcode-ai/fix-prompts/00-fix-order.md Queue table
# ---------------------------------------------------------------------------
# Look for table rows in the Queue section that:
#   1. Reference GitHub #<N>
#   2. Have a 🔲 status (not ✅ DONE / archived)
#
# Table rows look like:  | PE-051 | ... | GitHub #143. | 🔲 NEXT ... |
# The status cell is the last pipe-delimited column; a ✅ in that cell
# means the item is done.

check_c_xcode_queue() {
  [[ -f "$XCODE_QUEUE_FILE" ]] || return 0

  local pat
  pat="$(issue_pattern)"

  # Grab all table rows mentioning the issue number
  local matches
  matches="$(grep -F "$pat" "$XCODE_QUEUE_FILE" 2>/dev/null || true)"
  [[ -z "$matches" ]] && return 0

  local queued_entries=()

  while IFS= read -r row; do
    # Skip rows where the issue ref is in a ✅ DONE / archived cell.
    # The status cell is the final | ... | segment.
    # A queued row contains 🔲 and does NOT contain ✅ DONE.
    if echo "$row" | grep -qF '🔲'; then
      queued_entries+=("$row")
    elif echo "$row" | grep -qE '✅\s*(DONE|done|archived|CLOSED|closed)'; then
      : # done — skip
    elif echo "$row" | grep -qF '*(archived)*'; then
      : # archived — skip
    elif echo "$row" | grep -qE '^\s*\|.*\|\s*✅'; then
      : # done — skip
    else
      # Row mentions the issue but has no clear done marker — treat conservatively as queued
      queued_entries+=("$row")
    fi
  done <<<"$matches"

  if [[ ${#queued_entries[@]} -gt 0 ]]; then
    SKIP=1
    REASONS+=("Check C: #${ISSUE_NUM} found in QUEUED entry of xcode-ai/fix-prompts/00-fix-order.md")
  fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------

check_a_dev_qa
check_b_plans
check_c_xcode_queue

# ---------------------------------------------------------------------------
# Output result
# ---------------------------------------------------------------------------

if [[ $SKIP -eq 1 ]]; then
  echo "SKIP_AUTO_CLOSE: Issue #${ISSUE_NUM} is actively tracked. Do NOT close automatically."
  echo ""
  for reason in "${REASONS[@]}"; do
    echo "  • $reason"
  done
  echo ""
  echo "Action: Emit a status-comment on the issue instead of closing. Let a human close."
  exit 1
else
  echo "SAFE_TO_CLOSE: Issue #${ISSUE_NUM} — no active-tracking references found."
  exit 0
fi
