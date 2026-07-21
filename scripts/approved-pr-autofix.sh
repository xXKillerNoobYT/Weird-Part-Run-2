#!/usr/bin/env bash
# approved-pr-autofix.sh — Bounded Codex repair + merge path for approved same-repo PRs.
#
# This script is intentionally conservative:
# - same-repo PRs only (no forks / untrusted code)
# - approved review decision required before fixes or merge
# - one PR and one action per run
# - max attempts per PR head SHA, recorded via PR comments
# - Codex only; no Copilot
# - comments with explicit blockers instead of looping forever

set -euo pipefail
shopt -s nocasematch

REPO="${1:-${GITHUB_REPOSITORY:-}}"
BASE="${APPROVED_PR_AUTOFIX_BASE:-main}"
MAX_PRS="${APPROVED_PR_AUTOFIX_MAX_PRS:-20}"
MAX_ATTEMPTS="${APPROVED_PR_AUTOFIX_MAX_ATTEMPTS:-3}"
DRY_RUN="${APPROVED_PR_AUTOFIX_DRY_RUN:-0}"
TARGET_PR="${APPROVED_PR_AUTOFIX_PR_NUMBER:-}"
CODEX_MODEL="${APPROVED_PR_AUTOFIX_MODEL:-gpt-5.5}"
VALIDATE="${APPROVED_PR_AUTOFIX_VALIDATE:-auto}"
# Trusted first-party work can progress without a manual GitHub approval click;
# exact-head checks and sensitive-change exclusions still fail closed.
REQUIRE_APPROVAL="${APPROVED_PR_AUTOFIX_REQUIRE_APPROVAL:-1}"
# Comma-separated GitHub logins authorized to originate autonomous PR work.
# Same-repository location alone is not sufficient: collaborators can create
# branches, so PR author identity is checked separately.
TRUSTED_PR_AUTHORS="${APPROVED_PR_AUTOFIX_TRUSTED_PR_AUTHORS:-xXKillerNoobYT}"
SKIP_LABELS="${APPROVED_PR_AUTOFIX_SKIP_LABELS:-security,security-sensitive,manual-review,manual-merge,do-not-merge,no-autofix}"
SKIP_TITLE_REGEX="${APPROVED_PR_AUTOFIX_SKIP_TITLE_REGEX:-security|sqlcipher|encryption|auth|payment|credential|secret|keychain}"
MARKER="approved-pr-autofix:v1"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '${REPO:-<empty>}'" >&2
  exit 1
fi

for cmd in gh jq git codex; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: missing command: $cmd" >&2; exit 1; }
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

run_or_log() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run:'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  "$@"
}

dry_run_exit_action() {
  local description="$1"
  echo "dry-run: would $description"
  exit 0
}

comment_pr() {
  local number="$1" body="$2"
  run_or_log gh pr comment "$number" --repo "$REPO" --body "$body" >/dev/null 2>&1 || true
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

attempt_count_for_head() {
  local number="$1" head_sha="$2" comments_json
  comments_json="$(gh api "repos/$REPO/issues/$number/comments?per_page=100" 2>/dev/null || echo '[]')"
  jq -r --arg marker "$MARKER" --arg sha "$head_sha" \
    '[.[] | select((.body // "") | contains($marker)) | select((.body // "") | contains($sha))] | length' \
    <<<"$comments_json"
}

failure_fingerprint() {
  local text="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  fi
}

check_summary_for_sha() {
  local head_sha="$1"
  gh api "repos/$REPO/commits/$head_sha/check-runs?per_page=100" \
    --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed") | {name, conclusion, status, details_url, summary: (.output.summary // ""), text: (.output.text // "")} ]' 2>/dev/null || echo '[]'
}

pending_checks_for_sha() {
  local head_sha="$1"
  gh api "repos/$REPO/commits/$head_sha/check-runs?per_page=100" \
    --jq '[.check_runs[] | select(.status == "in_progress" or .status == "queued")] | length' 2>/dev/null || echo "0"
}

failing_checks_for_sha() {
  local head_sha="$1"
  gh api "repos/$REPO/commits/$head_sha/check-runs?per_page=100" \
    --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null and .status == "completed")] | length' 2>/dev/null || echo "0"
}

checkout_pr_branch() {
  local number="$1" branch="$2"
  git fetch origin "$BASE" "$branch"
  git checkout -B "$branch" "origin/$branch"
  git reset --hard "origin/$branch"
}

run_validation() {
  if [[ "$VALIDATE" == "none" ]]; then
    echo "validation disabled"
    return 0
  fi

  if [[ "$VALIDATE" != "auto" ]]; then
    echo "running configured validation: $VALIDATE"
    bash -lc "$VALIDATE"
    return $?
  fi

  if [[ -f core/Package.swift ]]; then
    echo "auto validation: swift test from core/"
    (cd core && swift test)
  elif [[ -f Package.swift ]]; then
    echo "auto validation: swift test"
    swift test
  elif [[ -f package.json ]]; then
    echo "auto validation: npm test when available"
    npm test --if-present
  else
    echo "auto validation: no known test manifest found; skipping"
  fi
}

codex_fix() {
  local number="$1" mode="$2" title="$3" head_sha="$4" failure_json="$5"
  local prompt_file=".tmp/approved-pr-autofix-prompt-$number.md"
  mkdir -p .tmp
  cat > "$prompt_file" <<EOF
You are fixing an already-approved private PR for Isaac's Weird-Part-Run-2 repo.

Hard constraints:
- Use OpenAI Codex only. Do not use or mention Copilot.
- Fix only PR #$number: $title
- Current PR head SHA before this attempt: $head_sha
- Mode: $mode
- Preserve the approved feature intent. Do not expand scope.
- Do not weaken tests, branch protection, required checks, security gates, or artifact guards.
- Do not commit secrets, tokens, payment data, browser cookies, or local runtime artifacts.
- If this is a merge conflict repair, resolve conflicts against origin/$BASE and preserve both sides where appropriate.
- If this is a runtime/build/test failure repair, make the smallest targeted code change that makes the failing checks pass.
- Avoid loops: do not make speculative broad rewrites. If the blocker is owner/admin-only, leave a concise note in your final output instead of changing code.

Failure/check context JSON:
$failure_json

Required final state:
- No conflict markers.
- Working tree contains only intentional source/workflow/test changes.
- Local validation can run without the same failure where possible.
EOF

  echo "running Codex repair for PR #$number ($mode)"
  codex exec --model "$CODEX_MODEL" --skip-git-repo-check "$(cat "$prompt_file")"
}

commit_and_push_if_changed() {
  local number="$1" mode="$2"
  if [[ -n "$(git status --porcelain)" ]]; then
    if git diff --check; then :; else
      echo "diff check failed; refusing to commit whitespace/conflict issues" >&2
      return 1
    fi
    if grep -RInE '<<<<<<<|=======|>>>>>>>' . \
      --exclude-dir=.git --exclude-dir=.tmp --exclude-dir=.build --exclude-dir=DerivedData \
      >/tmp/approved-pr-autofix-conflicts.txt 2>/dev/null; then
      echo "conflict markers remain:" >&2
      cat /tmp/approved-pr-autofix-conflicts.txt >&2
      return 1
    fi
    run_validation
    git add -A
    git commit -m "fix: approved PR autofix for #$number" -m "Mode: $mode" -m "Generated by bounded approved-pr-autofix workflow."
    run_or_log git push origin HEAD
    return 0
  fi
  echo "Codex produced no file changes."
  return 1
}

select_prs() {
  if [[ -n "$TARGET_PR" ]]; then
    gh pr view "$TARGET_PR" --repo "$REPO" --json number,title,isDraft,labels,author,headRepositoryOwner,headRefName,headRefOid,mergeStateStatus,mergeable,reviewDecision,autoMergeRequest | jq -c '[.]'
  else
    gh pr list --repo "$REPO" --base "$BASE" --state open --limit "$MAX_PRS" \
      --json number,title,isDraft,labels,author,headRepositoryOwner,headRefName,headRefOid,mergeStateStatus,mergeable,reviewDecision,autoMergeRequest
  fi
}

repo_owner="${REPO%%/*}"
echo "==> Approved PR autofix scan for $REPO base=$BASE max_attempts=$MAX_ATTEMPTS dry_run=$DRY_RUN"
prs_json="$(select_prs)"

while IFS= read -r pr; do
  number="$(jq -r '.number' <<<"$pr")"
  title="$(jq -r '.title' <<<"$pr")"
  is_draft="$(jq -r '.isDraft' <<<"$pr")"
  labels_json="$(jq -c '[.labels[]?.name]' <<<"$pr")"
  author="$(jq -r '.author.login // ""' <<<"$pr")"
  head_owner="$(jq -r '.headRepositoryOwner.login // ""' <<<"$pr")"
  head_branch="$(jq -r '.headRefName' <<<"$pr")"
  head_sha="$(jq -r '.headRefOid' <<<"$pr")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr")"
  mergeable="$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr")"
  review_decision="$(jq -r '.reviewDecision // ""' <<<"$pr")"

  echo ""
  echo "--- PR #$number: $title"
  echo "    author=${author:-<unknown>} review=$review_decision state=$merge_state mergeable=$mergeable draft=$is_draft branch=$head_branch sha=${head_sha:0:8}"

  [[ "$is_draft" == "true" ]] && { echo "    skip: draft"; continue; }
  [[ "$head_owner" != "$repo_owner" ]] && { echo "    skip: fork/untrusted head owner"; continue; }
  if ! is_trusted_author "$author"; then
    echo "    skip: PR author is not in APPROVED_PR_AUTOFIX_TRUSTED_PR_AUTHORS"
    continue
  fi
  if [[ "$REQUIRE_APPROVAL" == "1" && "$review_decision" != "APPROVED" ]]; then
    echo "    skip: approval required by APPROVED_PR_AUTOFIX_REQUIRE_APPROVAL"
    continue
  fi
  if has_skip_label "$labels_json" || [[ "$title" =~ $SKIP_TITLE_REGEX ]]; then
    echo "    skip: manual/security label or title"
    continue
  fi

  attempts="$(attempt_count_for_head "$number" "$head_sha")"
  if [[ "$attempts" -ge "$MAX_ATTEMPTS" ]]; then
    echo "    stop: max attempts reached for head $head_sha"
    comment_pr "$number" "🟡 **$MARKER**\n\nAutofix stopped for head \`$head_sha\` after $attempts/$MAX_ATTEMPTS attempts. This PR needs a human/agent handoff instead of another automated repair loop."
    exit 0
  fi

  # Conflicts/dirty branches get one bounded repair attempt.
  if [[ "$mergeable" == "CONFLICTING" || "$merge_state" == "DIRTY" ]]; then
    mode="merge-conflict"
    [[ "$DRY_RUN" == "1" ]] && dry_run_exit_action "attempt $mode repair for approved PR #$number at head $head_sha"
    comment_pr "$number" "🛠️ **$MARKER**\n\nAttempt $((attempts + 1))/$MAX_ATTEMPTS for head \`$head_sha\`. Mode: $mode. The PR is approved but has merge conflicts/dirty merge state; trying one bounded Codex repair on the self-hosted Mac runner."
    checkout_pr_branch "$number" "$head_branch"
    set +e
    git merge --no-ff --no-commit "origin/$BASE"
    merge_status=$?
    set -e
    codex_fix "$number" "$mode" "$title" "$head_sha" "{\"merge_status\":$merge_status,\"base\":\"$BASE\"}"
    commit_and_push_if_changed "$number" "$mode"
    exit 0
  fi

  pending="$(pending_checks_for_sha "$head_sha")"
  failing="$(failing_checks_for_sha "$head_sha")"
  if [[ "$pending" -gt 0 ]]; then
    echo "    skip: $pending check(s) still pending"
    continue
  fi

  if [[ "$failing" -gt 0 ]]; then
    mode="failing-checks"
    [[ "$DRY_RUN" == "1" ]] && dry_run_exit_action "attempt $mode repair for approved PR #$number at head $head_sha"
    failures="$(check_summary_for_sha "$head_sha")"
    fp="$(failure_fingerprint "$failures")"
    comment_pr "$number" "🛠️ **$MARKER**\n\nAttempt $((attempts + 1))/$MAX_ATTEMPTS for head \`$head_sha\`. Mode: $mode. Failure fingerprint: \`$fp\`. Trying one bounded Codex repair on the self-hosted Mac runner."
    checkout_pr_branch "$number" "$head_branch"
    codex_fix "$number" "$mode" "$title" "$head_sha" "$failures"
    commit_and_push_if_changed "$number" "$mode"
    exit 0
  fi

  if [[ "$merge_state" == "BEHIND" || "$merge_state" == "UNKNOWN" ]]; then
    echo "==> approved PR #$number is behind; updating branch, then exiting"
    run_or_log gh pr update-branch "$number" --repo "$REPO"
    exit 0
  fi

  if [[ "$merge_state" == "CLEAN" || "$merge_state" == "HAS_HOOKS" || "$merge_state" == "BLOCKED" ]]; then
    echo "==> approved PR #$number has no failing checks; queueing/performing squash merge"
    run_or_log gh pr merge "$number" --repo "$REPO" --squash --delete-branch --auto
    exit 0
  fi

  echo "    skip: unhandled merge state $merge_state"
done < <(jq -c 'sort_by(.number) | .[]' <<<"$prs_json")

echo "==> No approved actionable PR found."
