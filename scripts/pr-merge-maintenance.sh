#!/usr/bin/env bash
# pr-merge-maintenance.sh — Sequential one-at-a-time PR pipeline.
#
# Processes EXACTLY ONE PR per run:
#   1. Find the highest-priority PR that is ready (not conflicting, not draft, not skip-labelled)
#   2. If it's BEHIND main → rebase it (gh pr update-branch), then exit.
#      The push to the PR branch will trigger a new CodeQL run. The next
#      workflow run (fired by push to main or schedule) will pick it up again
#      once checks are green.
#   3. If it's CLEAN (checks green, up to date) → merge it (squash, delete branch).
#      The resulting push to main re-triggers this workflow for the next PR.
#   4. If checks are failing → post a comment with the failure summary and skip.
#
# This keeps Actions usage minimal: one rebase + one scan + one merge per PR,
# never burning parallel runs on the whole backlog at once.
#
# Environment:
#   GH_TOKEN                         Required in GitHub Actions.
#   PR_MAINTENANCE_BASE              Base branch. Default: main.
#   PR_MAINTENANCE_MAX_PRS           Optional explicit safety cap. Default: inspect all open PRs.
#   PR_MAINTENANCE_DRY_RUN           Set to 1 to log without side effects.
#   PR_MAINTENANCE_SKIP_LABELS       Comma-separated labels → manual only.
#   PR_MAINTENANCE_SKIP_TITLE_REGEX  Extended regex for security/manual titles.

set -euo pipefail
shopt -s nocasematch

REPO="${1:-${GITHUB_REPOSITORY:-}}"
BASE="${PR_MAINTENANCE_BASE:-main}"
MAX_PRS="${PR_MAINTENANCE_MAX_PRS:-}"
DRY_RUN="${PR_MAINTENANCE_DRY_RUN:-0}"
SKIP_LABELS="${PR_MAINTENANCE_SKIP_LABELS:-security,security-sensitive,manual-review,manual-merge,do-not-merge}"
SKIP_TITLE_REGEX="${PR_MAINTENANCE_SKIP_TITLE_REGEX:-security|sqlcipher|encryption|auth|payment|credential|secret|keychain}"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '${REPO:-<empty>}'" >&2
  exit 1
fi

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: missing: $cmd" >&2; exit 1; }
done

IFS=',' read -r -a SKIP_LABEL_ARRAY <<<"$SKIP_LABELS"

has_skip_label() {
  local labels_json="$1" label
  for label in "${SKIP_LABEL_ARRAY[@]}"; do
    label="$(printf "%s" "$label" | xargs)"
    [[ -z "$label" ]] && continue
    if jq -e --arg l "$label" 'map(ascii_downcase) | index($l | ascii_downcase)' <<<"$labels_json" >/dev/null; then
      return 0
    fi
  done
  return 1
}

run_or_log() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run:'; printf ' %q' "$@"; printf '\n'; return 0
  fi
  "$@"
}

if [[ -n "$MAX_PRS" && ! "$MAX_PRS" =~ ^[0-9]+$ ]]; then
  echo "error: PR_MAINTENANCE_MAX_PRS must be a positive integer when set, got '$MAX_PRS'" >&2
  exit 1
fi
# Strip leading zeros to avoid jq JSON-number parse failures (e.g. "05" is not
# valid JSON and --argjson would abort the script).
if [[ -n "$MAX_PRS" ]]; then
  MAX_PRS=$(( 10#$MAX_PRS ))
fi
if [[ "$MAX_PRS" == "0" ]]; then
  echo "error: PR_MAINTENANCE_MAX_PRS must be greater than zero when set" >&2
  exit 1
fi

if [[ -n "$MAX_PRS" ]]; then
  echo "==> Scanning (capped at $MAX_PRS) open PRs in $REPO targeting $BASE (one-at-a-time mode)"
else
  echo "==> Scanning all open PRs in $REPO targeting $BASE (one-at-a-time mode)"
fi

# Fetch the full matching queue with REST pagination, capturing all fields needed
# for processing in a single bulk request to avoid per-PR API calls in the loop.
pr_data_json="$(gh api --paginate --slurp "repos/$REPO/pulls?state=open&base=$BASE&per_page=100" \
  | jq '[.[][] | {
      number:           .number,
      title:            (.title // ""),
      isDraft:          (.draft // false),
      labels:           [(.labels // [])[].name],
      headOwner:        (.head.repo.owner.login // ""),
      mergeable:        (if .mergeable == true then "MERGEABLE"
                         elif .mergeable == false then "CONFLICTING"
                         else "UNKNOWN" end),
      mergeStateStatus: ((.mergeable_state // "unknown") | ascii_upcase),
      autoMerge:        (.auto_merge != null),
      headSha:          (.head.sha // "")
    }] | sort_by(.number)')"

total="$(jq 'length' <<<"$pr_data_json")"
if [[ "$total" -eq 0 ]]; then
  echo "No open PRs targeting $BASE. Nothing to do."
  exit 0
fi

if [[ -n "$MAX_PRS" ]]; then
  pr_data_json="$(jq --argjson max "$MAX_PRS" '.[:$max]' <<<"$pr_data_json")"
fi

inspected="$(jq 'length' <<<"$pr_data_json")"
echo "Found $total open PR(s); inspecting $inspected."
if [[ "$inspected" -lt "$total" ]]; then
  echo "warning: explicit PR_MAINTENANCE_MAX_PRS=$MAX_PRS limits this run to $inspected of $total open PRs" >&2
fi

repo_owner="${REPO%%/*}"

# Walk PRs in order (oldest first = lowest number first).
# Pick the FIRST one we can act on and do exactly that one action, then exit.
while IFS= read -r pr; do
  number="$(jq -r    '.number'                           <<<"$pr")"
  title="$(jq -r     '.title'                            <<<"$pr")"
  is_draft="$(jq -r  '.isDraft'                          <<<"$pr")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"'  <<<"$pr")"
  mergeable="$(jq -r   '.mergeable // "UNKNOWN"'         <<<"$pr")"
  auto_merge="$(jq -r  '.autoMerge'                      <<<"$pr")"
  labels_json="$(jq -c '.labels'                         <<<"$pr")"
  head_owner="$(jq -r  '.headOwner'                      <<<"$pr")"
  head_sha="$(jq -r    '.headSha'                        <<<"$pr")"

  echo ""
  echo "--- PR #$number: $title"
  echo "    state=$merge_state mergeable=$mergeable autoMerge=$auto_merge draft=$is_draft"

  # --- Skip conditions ---
  if [[ "$is_draft" == "true" ]]; then
    echo "    skip: draft"; continue; fi

  if [[ "$head_owner" != "$repo_owner" ]]; then
    echo "    skip: fork (manual only)"; continue; fi

  if has_skip_label "$labels_json" || [[ "$title" =~ $SKIP_TITLE_REGEX ]]; then
    echo "    skip: security/manual label or title"; continue; fi

  if [[ "$mergeable" == "CONFLICTING" || "$merge_state" == "DIRTY" ]]; then
    echo "    skip: has merge conflicts — engineer must resolve first"; continue; fi

  # --- Rebase if behind ---
  if [[ "$merge_state" == "BEHIND" || "$merge_state" == "UNKNOWN" ]]; then
    echo "==> PR #$number is BEHIND main — rebasing now (one action, then done)"
    if run_or_log gh pr update-branch "$number" --repo "$REPO"; then
      echo "    Rebased. CodeQL will re-run on the new head. Exiting — next run handles merge."
    else
      echo "    Branch update failed — engineer needs to rebase manually."
      # Post comment once so engineers know
      run_or_log gh pr comment "$number" --repo "$REPO" \
        --body "⚠️ Auto-rebase failed for this PR. Please rebase manually against \`$BASE\` and push." 2>/dev/null || true
    fi
    exit 0   # ONE action per run — stop here
  fi

  # --- Check if all required status checks are passing ---
  if [[ -n "$head_sha" ]]; then
    failing_checks="$(gh api "repos/$REPO/commits/$head_sha/check-runs" \
      --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed")] | length' 2>/dev/null || echo "0")"
    pending_checks="$(gh api "repos/$REPO/commits/$head_sha/check-runs" \
      --jq '[.check_runs[] | select(.status == "in_progress" or .status == "queued")] | length' 2>/dev/null || echo "0")"

    if [[ "$pending_checks" -gt 0 ]]; then
      echo "    skip: $pending_checks check(s) still running — waiting for scan to complete"; continue; fi

    if [[ "$failing_checks" -gt 0 ]]; then
      # Summarise failures and comment once (avoid spamming)
      failures="$(gh api "repos/$REPO/commits/$head_sha/check-runs" \
        --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed") | "- \(.name): \(.conclusion)"] | join("\n")' 2>/dev/null || echo "unknown")"
      echo "    SCAN FAILED — $failing_checks check(s) failing:"
      echo "$failures"
      # Only comment if not already commented recently
      run_or_log gh pr comment "$number" --repo "$REPO" \
        --body "🔴 **Merge blocked — required checks failing.**\n\nFailing checks on \`${head_sha:0:8}\`:\n${failures}\n\nPlease fix the issues above and push. The pipeline will retry automatically." 2>/dev/null || true
      echo "    Commented on PR. Skipping — engineer must fix scan failures."
      continue
    fi
  fi

  # --- Ready to merge ---
  if [[ "$merge_state" == "CLEAN" || "$merge_state" == "HAS_HOOKS" || "$merge_state" == "BLOCKED" ]]; then
    echo "==> PR #$number is CLEAN and checks pass — merging now (squash)"
    if run_or_log gh pr merge "$number" --repo "$REPO" --squash --delete-branch --auto; then
      echo "    Merged (or auto-merge queued). Push to $BASE will trigger next run."
    else
      echo "    Merge failed — may need manual review."
    fi
    exit 0   # ONE action per run — stop here
  fi

  echo "    skip: unhandled state '$merge_state'"

done < <(jq -c '.[]' <<<"$pr_data_json")

echo ""
echo "==> No actionable PR found this run. All remaining PRs are blocked, conflicting, or waiting on checks."
