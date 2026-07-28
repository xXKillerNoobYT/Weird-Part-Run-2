#!/usr/bin/env bash
# Regression coverage for exact-head review/merge verification. The fake gh
# records every merge request so each rejection path proves it never reaches gh pr merge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

pr_json() {
  local sha="$1"
  jq -nc --arg sha "$sha" '{
    number: 1,
    title: "Safe merge fixture",
    draft: false,
    labels: [],
    user: {login: "xXKillerNoobYT"},
    head: {repo: {owner: {login: "xXKillerNoobYT"}}, sha: $sha},
    mergeable: true,
    mergeable_state: "clean",
    auto_merge: null
  }'
}

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ "${1:-}" == "graphql" ]]; then
    case "${FIXTURE_MODE:?}" in
      review-api-failure) exit 1 ;;
      unresolved-review-thread)
        jq -nc '{data:{repository:{pullRequest:{headRefOid:"head-a",latestReviews:{nodes:[{author:{login:"copilot-pull-request-reviewer[bot]"},state:"APPROVED"}]},reviewThreads:{totalCount:1,nodes:[{isResolved:false}]}}}}}'
        exit 0 ;;
      merge-eligible)
        jq -nc '{data:{repository:{pullRequest:{headRefOid:"head-a",latestReviews:{nodes:[{author:{login:"copilot-pull-request-reviewer[bot]"},state:"APPROVED"}]},reviewThreads:{totalCount:0,nodes:[]}}}}}'
        exit 0 ;;
      *) echo "unexpected graphql fixture mode: $FIXTURE_MODE" >&2; exit 1 ;;
    esac
  fi

  endpoint=""
  for arg in "$@"; do
    case "$arg" in repos/*) endpoint="$arg" ;; esac
  done
  case "$endpoint" in
    *"/pulls?state=open&base=main&per_page=100")
      # gh api --paginate --slurp returns an array of pages. The list head is
      # intentionally stale; the script must not use it for eligibility.
      pr_json "head-listed" | jq -s '[.]'
      ;;
    "repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/1")
      count_file="$FIXTURE_DIR/current-pr-count"
      count=0; [[ -f "$count_file" ]] && count="$(cat "$count_file")"
      count=$((count + 1)); printf '%s' "$count" >"$count_file"
      if [[ "$FIXTURE_MODE" == "head-change-after-listing" && "$count" -ge 2 ]]; then
        pr_json "head-b"
      else
        pr_json "head-a"
      fi
      ;;
    "repos/xXKillerNoobYT/Weird-Part-Run-2/commits/head-a/check-runs"|"repos/xXKillerNoobYT/Weird-Part-Run-2/commits/head-b/check-runs")
      jq -nc '{check_runs:[]}'
      ;;
    *) echo "unexpected gh api endpoint: $endpoint ($*)" >&2; exit 1 ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  printf '%q ' "$@" >>"$FIXTURE_DIR/merge.log"
  printf '\n' >>"$FIXTURE_DIR/merge.log"
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

run_case() {
  local mode="$1" require_review="$2" expected="$3"
  local fixture_dir="$TMPDIR/$mode"
  local output
  mkdir -p "$fixture_dir"
  output="$(PATH="$TMPDIR:$PATH" FIXTURE_MODE="$mode" FIXTURE_DIR="$fixture_dir" \
    PR_MAINTENANCE_REQUIRE_COPILOT_REVIEW="$require_review" \
    "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  printf '%s\n' "$output" | grep -Fq "$expected"
  test ! -s "$fixture_dir/merge.log"
}

# Fresh list validation succeeds on head-a; the final fresh read sees head-b and
# must defer before invoking a merge.
run_case "head-change-after-listing" 0 "head changed during final verification"
run_case "review-api-failure" 1 "could not read review state (API failure)"
run_case "unresolved-review-thread" 1 "1 unresolved review thread(s)"

# A green exact-head review may reach the merge command only with the server-side
# match guard that rejects a post-verification force-push.
fixture_dir="$TMPDIR/merge-eligible"
mkdir -p "$fixture_dir"
PATH="$TMPDIR:$PATH" FIXTURE_MODE="merge-eligible" FIXTURE_DIR="$fixture_dir" \
  PR_MAINTENANCE_REQUIRE_COPILOT_REVIEW=1 \
  "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 >/dev/null
grep -Fq -- '--match-head-commit head-a' "$fixture_dir/merge.log"

echo "pr-merge-maintenance review-gate regression passed"
