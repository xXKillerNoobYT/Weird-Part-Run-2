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
# Same-repository branches can still be opened by collaborators; require an
# explicit PR-author allowlist before automated rebase or merge.
TRUSTED_PR_AUTHORS="${PR_MAINTENANCE_TRUSTED_PR_AUTHORS:-xXKillerNoobYT}"
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
IFS=',' read -r -a TRUSTED_AUTHOR_ARRAY <<<"$TRUSTED_PR_AUTHORS"

is_trusted_author() {
  local author="$1" candidate normalized_author normalized_candidate
  normalized_author="$(printf "%s" "$author" | tr '[:upper:]' '[:lower:]')"
  for candidate in "${TRUSTED_AUTHOR_ARRAY[@]}"; do
    candidate="$(printf "%s" "$candidate" | xargs)"
    [[ -z "$candidate" ]] && continue
    normalized_candidate="$(printf "%s" "$candidate" | tr '[:upper:]' '[:lower:]')"
    [[ "$normalized_candidate" == "$normalized_author" ]] && return 0
  done
  return 1
}

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

# The paginated list is only a queue-discovery snapshot. Never make a rebase or
# merge decision from it: a force-push can change the review/check target after
# the list request returns. Every candidate is re-read before eligibility and
# the merge path verifies that exact head again immediately before invoking gh.
fetch_current_pr() {
  local number="$1"
  gh api "repos/$REPO/pulls/$number" | jq -ce '{
    number:           .number,
    title:            (.title // ""),
    isDraft:          (.draft // false),
    labels:           [(.labels // [])[].name],
    author:           (.user.login // ""),
    headOwner:        (.head.repo.owner.login // ""),
    mergeable:        (if .mergeable == true then "MERGEABLE"
                       elif .mergeable == false then "CONFLICTING"
                       else "UNKNOWN" end),
    mergeStateStatus: ((.mergeable_state // "unknown") | ascii_upcase),
    autoMerge:        (.auto_merge != null),
    headSha:          (.head.sha // "")
  }'
}

load_pr_snapshot() {
  local snapshot="$1"
  title="$(jq -r     '.title'                            <<<"$snapshot")"
  is_draft="$(jq -r  '.isDraft'                          <<<"$snapshot")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"'  <<<"$snapshot")"
  mergeable="$(jq -r   '.mergeable // "UNKNOWN"'         <<<"$snapshot")"
  auto_merge="$(jq -r  '.autoMerge'                      <<<"$snapshot")"
  labels_json="$(jq -c '.labels'                         <<<"$snapshot")"
  author="$(jq -r      '.author // ""'                   <<<"$snapshot")"
  head_owner="$(jq -r  '.headOwner'                      <<<"$snapshot")"
  head_sha="$(jq -r    '.headSha'                        <<<"$snapshot")"
}

# Historical reviews survive rebases and force-pushes. For every named
# non-Copilot lane, GitHub's submitted_at timestamp is the primary ordering key
# and numeric review id breaks equal timestamps. The last exact-head submitted
# decision is authoritative: only an explicit Accept/Pass is eligible; Revise,
# missing verdicts, and malformed ordering data fail closed.
latest_current_head_lane_verdict() {
  local lane="$1" lane_pattern="$2" verified_head="$3" reviews_json="$4" verdict

  if ! verdict="$(jq -er --arg sha "$verified_head" --arg lane "$lane_pattern" '
    [ .[][]?
      | select(type == "object")
      | select(.commit_id == $sha)
      | select(.state == "APPROVED" or .state == "COMMENTED")
      | select((.body | type) == "string")
      | select(.body | test($lane; "i"))
      | select((.submitted_at | type) == "string")
      | select((.id | type) == "number")
      | {
          submittedAt: .submitted_at,
          submittedEpoch: (.submitted_at | fromdateiso8601),
          id: .id,
          body: .body
        }
    ]
    | if length == 0 then error("missing exact-head lane review") else
        sort_by(.submittedEpoch, .id) | last | .body
        | if test("(?im)\\bVerdict:\\s*Revise\\b") then "REVISE"
          elif test("(?im)\\bVerdict:\\s*(Accept|Pass)\\b") then "PASS"
          else error("latest lane review lacks an explicit verdict")
          end
      end
  ' <<<"$reviews_json" 2>/dev/null)"; then
    # This helper runs inside command substitution; write diagnostics to stderr so
    # a missing lane remains visible to the merge-maintenance log while the caller
    # can still capture only a PASS/REVISE verdict on stdout.
    echo "    skip: current-head $lane review evidence was malformed or incomplete — failing closed" >&2
    return 1
  fi

  printf '%s' "$verdict"
}

# Every required lane must have accepted evidence for the current head, and
# thread evidence must come from that same current pull request state.
require_current_head_review_lanes() {
  local number="$1" verified_head="$2" reviews_json thread_state review_head
  local localfirst_verdict gpt_verdict claude_verdict copilot_count thread_total unresolved

  if ! reviews_json="$(gh api --paginate --slurp "repos/$REPO/pulls/$number/reviews?per_page=100")"; then
    echo "    skip: could not read review evidence — failing closed"
    return 1
  fi
  if ! jq -e 'type == "array"' <<<"$reviews_json" >/dev/null 2>&1; then
    echo "    skip: review evidence was malformed — failing closed"
    return 1
  fi

  if ! localfirst_verdict="$(latest_current_head_lane_verdict "LocalFirst" "LocalFirst(?:Reviewer)?" "$verified_head" "$reviews_json")" ||
     ! gpt_verdict="$(latest_current_head_lane_verdict "GPTReviewer" "GPTReviewer" "$verified_head" "$reviews_json")" ||
     ! claude_verdict="$(latest_current_head_lane_verdict "ClaudeReviewer" "ClaudeReviewer" "$verified_head" "$reviews_json")"; then
    return 1
  fi
  copilot_count="$(jq --arg sha "$verified_head" '[.[][]? | select(.commit_id == $sha) | select(.state == "APPROVED" or .state == "COMMENTED") | select((.user.login // "") == "copilot-pull-request-reviewer" or (.user.login // "") == "copilot-pull-request-reviewer[bot]")] | length' <<<"$reviews_json" 2>/dev/null || true)"

  if [[ ! "$copilot_count" =~ ^[0-9]+$ ]]; then
    echo "    skip: review evidence was malformed — failing closed"
    return 1
  fi
  if [[ "$localfirst_verdict" != "PASS" || "$gpt_verdict" != "PASS" || "$claude_verdict" != "PASS" || "$copilot_count" -eq 0 ]]; then
    echo "    skip: latest current-head review lane rejected (LocalFirst=$localfirst_verdict GPT=$gpt_verdict Claude=$claude_verdict Copilot=$copilot_count)"
    return 1
  fi

  if ! thread_state="$(gh api graphql -f query="query { repository(owner: \"$repo_owner\", name: \"$repo_name\") { pullRequest(number: $number) { headRefOid reviewThreads(first: 100) { totalCount nodes { isResolved } } } } }")"; then
    echo "    skip: could not read review thread state — failing closed"
    return 1
  fi
  review_head="$(jq -r '.data.repository.pullRequest.headRefOid // empty' <<<"$thread_state" 2>/dev/null || true)"
  thread_total="$(jq -r '.data.repository.pullRequest.reviewThreads.totalCount // empty' <<<"$thread_state" 2>/dev/null || true)"
  unresolved="$(jq '[.data.repository.pullRequest.reviewThreads.nodes[]? | select(.isResolved == false)] | length' <<<"$thread_state" 2>/dev/null || true)"
  if [[ "$review_head" != "$verified_head" || ! "$thread_total" =~ ^[0-9]+$ || ! "$unresolved" =~ ^[0-9]+$ || "$thread_total" -gt 100 || "$unresolved" -gt 0 ]]; then
    echo "    skip: review threads are unresolved or cannot be fully verified for current head (head=${review_head:0:8} total=${thread_total:-unknown} unresolved=${unresolved:-unknown})"
    return 1
  fi

  echo "    current-head review lanes satisfied (LocalFirst, GPT, Claude, Copilot; threads resolved)"
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
      author:           (.user.login // ""),
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
repo_name="${REPO##*/}"

# Walk PRs in order (oldest first = lowest number first).
# Pick the FIRST one we can act on and do exactly that one action, then exit.
while IFS= read -r pr; do
  number="$(jq -r    '.number'                           <<<"$pr")"
  # The list record is deliberately not used to choose an action. Refetch first
  # so every eligibility check below is bound to one current PR snapshot.
  if ! current_pr="$(fetch_current_pr "$number")"; then
    echo "    skip: could not refresh current PR state — not acting on stale queue data"
    continue
  fi
  load_pr_snapshot "$current_pr"

  echo ""
  echo "--- PR #$number: $title"
  echo "    refreshed head=${head_sha:0:8} author=${author:-<unknown>} state=$merge_state mergeable=$mergeable autoMerge=$auto_merge draft=$is_draft"

  # --- Skip conditions, evaluated from the fresh PR snapshot ---
  if [[ "$is_draft" == "true" ]]; then
    echo "    skip: draft"; continue; fi

  if [[ "$head_owner" != "$repo_owner" ]]; then
    echo "    skip: fork (manual only)"; continue; fi

  if ! is_trusted_author "$author"; then
    echo "    skip: PR author is not in PR_MAINTENANCE_TRUSTED_PR_AUTHORS"; continue; fi

  if has_skip_label "$labels_json" || [[ "$title" =~ $SKIP_TITLE_REGEX ]]; then
    echo "    skip: security/manual label or title"; continue; fi

  if [[ "$mergeable" == "CONFLICTING" || "$merge_state" == "DIRTY" ]]; then
    echo "    skip: has merge conflicts — engineer must resolve first"; continue; fi

  # --- Resolve UNKNOWN mergeability before acting ---
  # Refresh the full PR rather than only mergeable_state so a head change while
  # GitHub computes mergeability cannot carry stale review/check evidence forward.
  if [[ "$merge_state" == "UNKNOWN" ]]; then
    for _attempt in 1 2 3 4 5; do
      if ! current_pr="$(fetch_current_pr "$number")"; then
        break
      fi
      load_pr_snapshot "$current_pr"
      [[ "$merge_state" != "UNKNOWN" ]] && break
      sleep 3
    done
    echo "    resolved mergeability: state=$merge_state"
    if [[ "$merge_state" == "UNKNOWN" ]]; then
      echo "    skip: mergeability still computing or refresh failed — next run retries"; continue; fi
    if [[ "$mergeable" == "CONFLICTING" || "$merge_state" == "DIRTY" ]]; then
      echo "    skip: has merge conflicts — engineer must resolve first"; continue; fi
  fi

  # --- Rebase if behind ---
  if [[ "$merge_state" == "BEHIND" ]]; then
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
  if [[ -z "$head_sha" ]]; then
    echo "    skip: refreshed PR has no head SHA — cannot verify checks"
    continue
  fi
  if ! check_runs="$(gh api "repos/$REPO/commits/$head_sha/check-runs")"; then
    echo "    skip: could not read checks for refreshed head ${head_sha:0:8} — not merging on unknown check state"
    continue
  fi
  if ! failing_checks="$(jq -er '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed")] | length' <<<"$check_runs")"; then
    echo "    skip: malformed check response for refreshed head ${head_sha:0:8} — not merging"
    continue
  fi
  if ! pending_checks="$(jq -er '[.check_runs[] | select(.status == "in_progress" or .status == "queued")] | length' <<<"$check_runs")"; then
    echo "    skip: malformed check response for refreshed head ${head_sha:0:8} — not merging"
    continue
  fi

  if [[ "$pending_checks" -gt 0 ]]; then
    echo "    skip: $pending_checks check(s) still running — waiting for scan to complete"; continue; fi

  if [[ "$failing_checks" -gt 0 ]]; then
      # Summarise failures and comment once (avoid spamming)
      failures="$(jq -r '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed") | "- \(.name): \(.conclusion)"] | join("\n")' <<<"$check_runs")"
      echo "    SCAN FAILED — $failing_checks check(s) failing:"
      echo "$failures"
      # Only comment if not already commented recently
      run_or_log gh pr comment "$number" --repo "$REPO" \
        --body "🔴 **Merge blocked — required checks failing.**\n\nFailing checks on \`${head_sha:0:8}\`:\n${failures}\n\nPlease fix the issues above and push. The pipeline will retry automatically." 2>/dev/null || true
      echo "    Commented on PR. Skipping — engineer must fix scan failures."
      continue
  fi

  # This is intentionally unconditional: workflow/environment configuration
  # cannot downgrade the mandatory LocalFirst → GPT → Claude → Copilot chain.
  if ! require_current_head_review_lanes "$number" "$head_sha"; then
    continue
  fi

  # --- Ready to merge ---
  if [[ "$merge_state" == "CLEAN" || "$merge_state" == "HAS_HOOKS" ]]; then
    # A second fresh snapshot closes the list→verify→merge TOCTOU window. The
    # server-side match guard covers the remaining race after this GET.
    if ! final_pr="$(fetch_current_pr "$number")"; then
      echo "    skip: could not refresh final PR state — not invoking merge"
      continue
    fi
    final_head="$(jq -r '.headSha' <<<"$final_pr")"
    final_state="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$final_pr")"
    if [[ "$final_head" != "$head_sha" ]]; then
      echo "    skip: PR head changed during final verification (${head_sha:0:8} -> ${final_head:0:8}) — deferring without merge"
      continue
    fi
    if [[ "$final_state" != "CLEAN" && "$final_state" != "HAS_HOOKS" ]]; then
      echo "    skip: merge state changed during final verification ($merge_state -> $final_state) — deferring without merge"
      continue
    fi
    echo "==> PR #$number is $final_state at verified head ${head_sha:0:8} — merging now (squash)"
    if run_or_log gh pr merge "$number" --repo "$REPO" --squash --delete-branch --auto --match-head-commit "$head_sha"; then
      echo "    Merged (or auto-merge queued). Push to $BASE will trigger next run."
    else
      echo "    Merge failed — the head may have changed or manual review is needed."
    fi
    exit 0   # ONE action per run — stop here
  fi

  # BLOCKED past this point means branch protection still refuses the merge
  # even though no skip condition above caught a cause — typically a required
  # check context that was never delivered for this head (cancelled/superseded
  # run), which no re-merge attempt can fix. Treating BLOCKED as mergeable
  # queued an auto-merge that never fired and exited, head-of-line blocking
  # the train on the same PR every run (observed stuck on #1431 for days).
  # Skipping is free: it does not consume this run's one action.
  if [[ "$merge_state" == "BLOCKED" ]]; then
    echo "    skip: BLOCKED by branch protection (likely an undelivered required check) — needs a re-run of its checks, moving on"
    continue
  fi

  echo "    skip: unhandled state '$merge_state'"

done < <(jq -c '.[]' <<<"$pr_data_json")

echo ""
echo "==> No actionable PR found this run. All remaining PRs are blocked, conflicting, or waiting on checks."
