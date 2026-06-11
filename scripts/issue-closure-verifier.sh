#!/usr/bin/env bash
# issue-closure-verifier.sh — Weekly audit: review issues closed in the last
# N days, re-open any that are still actively tracked per the guard checks.
#
# This is the long-term "safety net" guard described in issue #233. It
# complements issue-auto-close-guard.sh (which gates at close-time) by
# catching any issues that slipped through (e.g. closed by a concurrent run,
# closed via UI, or closed before the guard was in place).
#
# Usage:
#   scripts/issue-closure-verifier.sh [--repo owner/repo] [--days N]
#                                     [--dry-run] [--output-dir path]
#
# Environment variables (overridden by flags):
#   GITHUB_REPO                   Default repo (owner/repo).
#   ISSUE_VERIFIER_LOOKBACK_DAYS  Default lookback window. Default: 30.
#   ISSUE_VERIFIER_DRY_RUN        Set to 1 for dry-run (no reopen/comment).
#   ISSUE_VERIFIER_OUTPUT_DIR     Output directory. Default: .tmp/issue-closure-verifier
#
# Requirements: gh, jq, bash 4+
#
# Exit codes:
#   0  — Audit complete (reopened 0 or more issues).
#   1  — Fatal error (gh/jq missing, bad args, etc.).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/issue-closure-verifier.sh [--repo owner/repo] [--days N]
                                    [--dry-run] [--output-dir path]

Flags:
  --repo owner/repo   GitHub repository. Default: GITHUB_REPO env or xXKillerNoobYT/Weird-Part-Run-2
  --days N            Lookback window in days. Default: 30
  --dry-run           Print actions without reopening or commenting
  --output-dir path   Where to write audit log. Default: .tmp/issue-closure-verifier

Environment:
  GITHUB_REPO                   Fallback repo if --repo not supplied
  ISSUE_VERIFIER_LOOKBACK_DAYS  Fallback lookback days
  ISSUE_VERIFIER_DRY_RUN        Set to 1 to enable dry-run
  ISSUE_VERIFIER_OUTPUT_DIR     Fallback output directory
EOF
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

for cmd in gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

REPO_ARG=""
DAYS_ARG=""
DRY_RUN_ARG=""
OUT_DIR_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ARG="${2:?error: --repo requires owner/repo}"
      shift 2
      ;;
    --days)
      DAYS_ARG="${2:?error: --days requires a positive integer}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN_ARG=1
      shift
      ;;
    --output-dir)
      OUT_DIR_ARG="${2:?error: --output-dir requires a path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO="${REPO_ARG:-${GITHUB_REPO:-xXKillerNoobYT/Weird-Part-Run-2}}"
LOOKBACK_DAYS="${DAYS_ARG:-${ISSUE_VERIFIER_LOOKBACK_DAYS:-30}}"
DRY_RUN="${DRY_RUN_ARG:-${ISSUE_VERIFIER_DRY_RUN:-0}}"
OUT_DIR="${OUT_DIR_ARG:-${ISSUE_VERIFIER_OUTPUT_DIR:-.tmp/issue-closure-verifier}}"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '$REPO'" >&2
  exit 1
fi
if [[ ! "$LOOKBACK_DAYS" =~ ^[0-9]+$ || "$LOOKBACK_DAYS" -lt 1 ]]; then
  echo "error: --days must be a positive integer, got '$LOOKBACK_DAYS'" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/issue-auto-close-guard.sh"

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP_DIR="${STAMP//:/-}"
RUN_DIR="$OUT_DIR/$STAMP_DIR"
LOG_PATH="$RUN_DIR/audit.md"
LATEST_LOG="$OUT_DIR/latest-audit.md"

mkdir -p "$RUN_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_or_log() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

log() {
  echo "$*" | tee -a "$LOG_PATH"
}

# ---------------------------------------------------------------------------
# Fetch recently closed issues
# ---------------------------------------------------------------------------

SINCE_DATE="$(date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v "-${LOOKBACK_DAYS}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || { echo "error: cannot compute date - ${LOOKBACK_DAYS}d ago (need GNU or BSD date)" >&2; exit 1; })"

log "# Issue Closure Verifier — Audit Run"
log ""
log "- Repository: \`${REPO}\`"
log "- Run timestamp (UTC): \`${STAMP}\`"
log "- Lookback window: \`${LOOKBACK_DAYS} days\` (since \`${SINCE_DATE}\`)"
log "- Dry-run: \`${DRY_RUN}\`"
log "- Guard script: \`${GUARD_SCRIPT}\`"
log ""

log "## Fetching recently closed issues..."

ISSUES_JSON="$RUN_DIR/closed-issues.json"

gh issue list \
  --repo "$REPO" \
  --state closed \
  --limit 300 \
  --json number,title,state,closedAt,url \
  > "$ISSUES_JSON"

# Filter to issues closed within the lookback window
RECENT_JSON="$RUN_DIR/recent-closed.json"
jq --arg since "$SINCE_DATE" \
  'map(select(.state == "CLOSED" and .closedAt >= $since))' \
  "$ISSUES_JSON" > "$RECENT_JSON"

TOTAL="$(jq 'length' "$RECENT_JSON")"
log "- Issues closed in last ${LOOKBACK_DAYS} days: \`${TOTAL}\`"
log ""

if [[ "$TOTAL" -eq 0 ]]; then
  log "Nothing to verify — no issues closed in this window."
  cp "$LOG_PATH" "$LATEST_LOG"
  echo "Audit complete. 0 issues scanned. 0 reopened."
  exit 0
fi

# ---------------------------------------------------------------------------
# Check each recently closed issue against the guard
# ---------------------------------------------------------------------------

log "## Per-Issue Results"
log ""
log "| Issue | Title | Guard Result | Action |"
log "|-------|-------|--------------|--------|"

REOPENED=0
SKIPPED=0
SAFE=0

while IFS= read -r issue; do
  number="$(echo "$issue" | jq -r '.number')"
  title="$(echo "$issue" | jq -r '.title')"
  closed_at="$(echo "$issue" | jq -r '.closedAt')"

  # Run the guard — capture output, do not let it abort the loop on exit 1
  guard_output=""
  guard_exit=0
  if [[ -x "$GUARD_SCRIPT" ]]; then
    guard_output="$("$GUARD_SCRIPT" "$number" "$REPO_ROOT" 2>&1)" || guard_exit=$?
  else
    # Guard script not executable / not present — treat as safe
    guard_exit=0
    guard_output="guard script not found at $GUARD_SCRIPT — skipping check"
  fi

  if [[ "$guard_exit" -eq 0 ]]; then
    # Safe — no active tracking found
    log "| #${number} | ${title} | SAFE | — |"
    SAFE=$((SAFE + 1))
    continue
  fi

  # Guard says skip — issue is actively tracked
  SKIPPED=$((SKIPPED + 1))

  # Build a comment body explaining the reopen
  COMMENT_BODY="**Issue Closure Verifier — Auto-Reopen**

This issue was closed on \`${closed_at}\` but the \`issue-auto-close-guard\` detected that it is still actively tracked:

\`\`\`
${guard_output}
\`\`\`

The issue has been automatically reopened. A human should review and close it once the tracked work is genuinely complete.

*Triggered by: \`scripts/issue-closure-verifier.sh\` — see \`docs/issue-closure-audit-tracker.md\` for audit history.*"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "| #${number} | ${title} | TRACKED (guard exit=${guard_exit}) | dry-run: would reopen + comment |"
    run_or_log gh issue comment "$number" --repo "$REPO" --body "$COMMENT_BODY"
    run_or_log gh issue reopen "$number" --repo "$REPO"
    REOPENED=$((REOPENED + 1))
  else
    # Post comment then reopen
    if gh issue comment "$number" --repo "$REPO" --body "$COMMENT_BODY" >/dev/null 2>&1; then
      if gh issue reopen "$number" --repo "$REPO" >/dev/null 2>&1; then
        log "| #${number} | ${title} | TRACKED | ✅ REOPENED |"
        REOPENED=$((REOPENED + 1))
      else
        log "| #${number} | ${title} | TRACKED | ⚠️ comment posted, reopen FAILED |"
      fi
    else
      log "| #${number} | ${title} | TRACKED | ⚠️ comment + reopen FAILED |"
    fi
  fi

done < <(jq -c '.[]' "$RECENT_JSON")

log ""
log "## Summary"
log ""
log "- Total scanned: \`${TOTAL}\`"
log "- Safe to close (verified): \`${SAFE}\`"
log "- Actively tracked (guard triggered): \`${SKIPPED}\`"
log "- Reopened: \`${REOPENED}\`"
log ""
log "*See \`docs/issue-closure-audit-tracker.md\` for full audit history.*"

cp "$LOG_PATH" "$LATEST_LOG"

if [[ ! -s "$LATEST_LOG" ]]; then
  echo "error: audit log is empty — something went wrong" >&2
  exit 1
fi

echo ""
echo "wrote: $LOG_PATH"
echo "wrote: $LATEST_LOG"
echo "Audit complete. ${TOTAL} scanned. ${REOPENED} reopened."
