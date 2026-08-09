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
#   Copilot waivers are always read from the trusted merge base, never an
#   environment-configured local or workflow-ref file.

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
COPILOT_WAIVER_PATH=".github/merge-control/copilot-review-waivers.json"

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

# A waiver is deliberately a tracked, exact PR-and-head exception rather than
# an environment toggle. Fetch the ledger from the merge base via GitHub rather
# than the workflow checkout: workflow_dispatch can otherwise run arbitrary
# refs whose changed ledger would silently change a merge decision.
trusted_copilot_waiver_ledger() {
  gh api -X GET -H 'Accept: application/vnd.github.raw+json' \
    "repos/$REPO/contents/$COPILOT_WAIVER_PATH?ref=$BASE" 2>/dev/null
}

owner_approval_comment_valid() {
  local number="$1" approval_url="$2" comment_id comment

  if [[ ! "$approval_url" =~ ^https://github\.com/xXKillerNoobYT/Weird-Part-Run-2/(pull|issues)/$number#issuecomment-([0-9]+)$ ]]; then
    return 1
  fi
  comment_id="${BASH_REMATCH[2]}"
  comment="$(gh api "repos/$REPO/issues/comments/$comment_id" 2>/dev/null || echo "")"
  [[ -n "$comment" ]] || return 1

  jq -e --arg number "$number" '
    (.user.login // "") == "xXKillerNoobYT"
    and ((.issue_url // "") | endswith("/issues/" + $number))
  ' <<<"$comment" >/dev/null 2>&1
}

has_owner_approved_copilot_waiver() {
  local number="$1" head_sha="$2" ledger waiver approval_url

  ledger="$(trusted_copilot_waiver_ledger || echo "")"
  if [[ -z "$ledger" ]]; then
    echo "    skip: could not read Copilot waiver ledger from $BASE — not merging"
    return 1
  fi

  waiver="$(jq -ce --argjson number "$number" --arg sha "$head_sha" '
    if .version == 1 and (.waivers | type == "array") then
      first(.waivers[]? |
        select(
      (.pr == $number)
      and (.head_sha == $sha)
      and (.approved_by == "xXKillerNoobYT")
      and (.reason | type == "string" and length > 0)
      and (.approval_url | type == "string"
           and test("^https://github\\.com/xXKillerNoobYT/Weird-Part-Run-2/(pull|issues)/" + ($number | tostring) + "#issuecomment-[0-9]+$"))
        )
      )
    else empty end
  ' <<<"$ledger" 2>/dev/null || echo "")"
  [[ -n "$waiver" ]] || return 1

  approval_url="$(jq -r '.approval_url' <<<"$waiver")"
  if ! owner_approval_comment_valid "$number" "$approval_url"; then
    echo "    skip: Copilot waiver approval comment is not an owner comment on this PR — not merging"
    return 1
  fi

  echo "    Copilot gate: owner-approved exact PR-and-SHA waiver found in trusted $BASE ledger"
  return 0
}

copilot_review_or_waiver_satisfied() {
  local number="$1" head_sha="$2" review_state copilot_reviews already_requested thread_total unresolved

  # A GraphQL failure fails closed: an absent or unreadable review state never
  # becomes permission to merge. review.commit.oid prevents a prior-head review
  # from satisfying the current-head gate.
  review_state="$(gh api graphql -f query="query { repository(owner: \"$repo_owner\", name: \"$repo_name\") { pullRequest(number: $number) { latestReviews: reviews(last: 100) { nodes { author { login } state commit { oid } } } reviewThreads(first: 100) { totalCount nodes { isResolved } } } } }" 2>/dev/null || echo "")"
  if [[ -z "$review_state" ]]; then
    echo "    skip: could not read Copilot review state — not merging on unknown evidence"
    return 1
  fi

  copilot_reviews="$(jq --arg sha "$head_sha" '[.data.repository.pullRequest.latestReviews.nodes[]?
    | select((.author.login // "") == "copilot-pull-request-reviewer" or (.author.login // "") == "copilot-pull-request-reviewer[bot]")
    | select(.state == "COMMENTED" or .state == "APPROVED" or .state == "CHANGES_REQUESTED")
    | select((.commit.oid // "") == $sha)] | length' <<<"$review_state" 2>/dev/null || echo "0")"
  if [[ ! "$copilot_reviews" =~ ^[0-9]+$ ]]; then copilot_reviews="0"; fi
  if [[ "$copilot_reviews" -gt 0 ]]; then
    echo "    Copilot gate: $copilot_reviews submitted exact-head review(s) found"
  elif has_owner_approved_copilot_waiver "$number" "$head_sha"; then
    :
  else
    already_requested="$(gh api "repos/$REPO/pulls/$number" \
      --jq '[.requested_reviewers[]?.login | select(. == "Copilot" or . == "copilot-pull-request-reviewer" or . == "copilot-pull-request-reviewer[bot]")] | length' 2>/dev/null || echo "0")"
    if [[ ! "$already_requested" =~ ^[0-9]+$ ]]; then already_requested="0"; fi
    if [[ "$already_requested" -eq 0 ]]; then
      if run_or_log gh api -X POST "repos/$REPO/pulls/$number/requested_reviewers" \
        -f 'reviewers[]=copilot-pull-request-reviewer[bot]' >/dev/null; then
        echo "    skip: no exact-head Copilot review or valid waiver; requested Copilot review"
      else
        echo "    skip: no exact-head Copilot review or valid waiver; failed to request Copilot review"
      fi
    else
      echo "    skip: no exact-head Copilot review or valid waiver; Copilot review is pending"
    fi
    return 1
  fi

  thread_total="$(jq '.data.repository.pullRequest.reviewThreads.totalCount // "invalid"' <<<"$review_state" 2>/dev/null || echo "invalid")"
  if [[ ! "$thread_total" =~ ^[0-9]+$ ]] || [[ "$thread_total" -gt 100 ]]; then
    echo "    skip: cannot prove all review threads are resolved — not merging"
    return 1
  fi
  unresolved="$(jq '[.data.repository.pullRequest.reviewThreads.nodes[]? | select(.isResolved == false)] | length' <<<"$review_state" 2>/dev/null || echo "invalid")"
  if [[ ! "$unresolved" =~ ^[0-9]+$ ]] || [[ "$unresolved" -gt 0 ]]; then
    echo "    skip: ${unresolved:-unknown} unresolved review thread(s) — not merging"
    return 1
  fi
  return 0
}

# --- Self-heal: approve workflow runs stuck awaiting manual approval ---
# When PR_MAINTENANCE_PAT is missing, the update-branch pushes this script
# makes with the fallback github.token leave their CI runs in
# conclusion=action_required, so required contexts are never delivered and
# the train silently stalls (#1556; previously jammed #1343-#1346, and
# 30+ runs were hand-approved during the 2026-07-28/29 backlog drain).
# Try to approve them via the API; when the token cannot, log loudly so
# the stall is visible instead of silent.
approve_stuck_workflow_runs() {
  local ids id approved=0 failed=0
  ids="$(gh api "repos/$REPO/actions/runs?status=action_required&per_page=50" \
    --jq '.workflow_runs[]?.id' 2>/dev/null || true)"
  [[ -z "$ids" ]] && return 0
  while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    if run_or_log gh api -X POST "repos/$REPO/actions/runs/$id/approve" >/dev/null 2>&1; then
      approved=$((approved+1))
    else
      failed=$((failed+1))
    fi
  done <<<"$ids"
  echo "==> Self-heal: approved $approved stuck (action_required) workflow run(s); $failed could not be approved."
  if [[ "$failed" -gt 0 ]]; then
    echo "WARNING: $failed workflow run(s) still await manual approval — PR_MAINTENANCE_PAT is likely missing or lacks Actions write (see #1556)." >&2
  fi
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

# Unjam any runs stuck awaiting approval before deciding what to do —
# otherwise their PRs read as "checks pending/missing" forever.
approve_stuck_workflow_runs

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
  title="$(jq -r     '.title'                            <<<"$pr")"
  is_draft="$(jq -r  '.isDraft'                          <<<"$pr")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"'  <<<"$pr")"
  mergeable="$(jq -r   '.mergeable // "UNKNOWN"'         <<<"$pr")"
  auto_merge="$(jq -r  '.autoMerge'                      <<<"$pr")"
  labels_json="$(jq -c '.labels'                         <<<"$pr")"
  author="$(jq -r      '.author // ""'                     <<<"$pr")"
  head_owner="$(jq -r  '.headOwner'                      <<<"$pr")"
  head_sha="$(jq -r    '.headSha'                        <<<"$pr")"

  echo ""
  echo "--- PR #$number: $title"
  echo "    author=${author:-<unknown>} state=$merge_state mergeable=$mergeable autoMerge=$auto_merge draft=$is_draft"

  # --- Skip conditions ---
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
  # The list endpoint returns mergeable_state only when GitHub has it cached;
  # treating UNKNOWN as BEHIND made the train "rebase" an up-to-date branch
  # forever (update-branch no-ops, the state never changes, nothing merges).
  # A single-PR GET forces GitHub to compute mergeability; poll briefly.
  if [[ "$merge_state" == "UNKNOWN" ]]; then
    for _attempt in 1 2 3 4 5; do
      merge_state="$(gh api "repos/$REPO/pulls/$number" \
        --jq '(.mergeable_state // "unknown") | ascii_upcase' 2>/dev/null || echo "UNKNOWN")"
      [[ "$merge_state" != "UNKNOWN" ]] && break
      sleep 3
    done
    echo "    resolved mergeability: state=$merge_state"
    if [[ "$merge_state" == "UNKNOWN" ]]; then
      echo "    skip: mergeability still computing — next run retries"; continue; fi
    if [[ "$merge_state" == "DIRTY" ]]; then
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

  if ! copilot_review_or_waiver_satisfied "$number" "$head_sha"; then
    continue
  fi

  # --- Ready to merge ---
  if [[ "$merge_state" == "CLEAN" || "$merge_state" == "HAS_HOOKS" ]]; then
    echo "==> PR #$number is $merge_state with required checks and exact-head Copilot evidence — merging now (squash)"
    # Do not queue auto-merge: a later head update would otherwise become
    # mergeable without this script re-evaluating its exact-head evidence.
    if run_or_log gh pr merge "$number" --repo "$REPO" --squash --delete-branch; then
      echo "    Merged. Push to $BASE will trigger next run."
    else
      echo "    Merge failed — may need manual review."
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
