#!/usr/bin/env bash
# Regression coverage for exact-head review/merge verification. Every rejection
# fixture records attempted merges and asserts that no gh pr merge path is taken.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

pr_json() {
  jq -nc --arg sha "$1" '{number:1,title:"Safe merge fixture",draft:false,labels:[],user:{login:"xXKillerNoobYT"},head:{repo:{owner:{login:"xXKillerNoobYT"}},sha:$sha},mergeable:true,mergeable_state:"clean",auto_merge:null}'
}
reviews_json() {
  jq -nc --arg sha "$1" --arg mode "$FIXTURE_MODE" '[
    [
      {id:101,submitted_at:"2026-07-28T10:00:00Z",commit_id:$sha,state:"APPROVED",body:"LocalFirst\nVerdict: Pass",user:{login:"xXKillerNoobYT"}},
      {id:102,submitted_at:"2026-07-28T10:01:00Z",commit_id:$sha,state:"APPROVED",body:"GPTReviewer\nVerdict: Accept",user:{login:"xXKillerNoobYT"}},
      {id:103,submitted_at:"2026-07-28T10:02:00Z",commit_id:$sha,state:"APPROVED",body:"ClaudeReviewer\nVerdict: Accept",user:{login:"xXKillerNoobYT"}},
      {id:104,submitted_at:"2026-07-28T10:03:00Z",commit_id:$sha,state:"APPROVED",body:"Copilot review",user:{login:"copilot-pull-request-reviewer[bot]"}}
    ] +
    (if $mode == "later-gpt-revise" then
      [{id:105,submitted_at:"2026-07-28T10:04:00Z",commit_id:$sha,state:"COMMENTED",body:"GPTReviewer\nVerdict: Revise",user:{login:"xXKillerNoobYT"}}]
     else [] end)
  ]'
}

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ "${1:-}" == "graphql" ]]; then
    if [[ "$FIXTURE_MODE" == "review-thread-api-failure" ]]; then
      exit 1
    elif [[ "$FIXTURE_MODE" == "unresolved-review-thread" ]]; then
      jq -nc '{data:{repository:{pullRequest:{headRefOid:"head-a",reviewThreads:{totalCount:1,nodes:[{isResolved:false}]}}}}}'
    else
      jq -nc '{data:{repository:{pullRequest:{headRefOid:"head-a",reviewThreads:{totalCount:0,nodes:[]}}}}}'
    fi
    exit 0
  fi

  endpoint=""
  for arg in "$@"; do case "$arg" in repos/*) endpoint="$arg" ;; esac; done
  case "$endpoint" in
    *"/pulls?state=open&base=main&per_page=100")
      pr_json "head-listed" | jq -s '[.]' ;;
    "repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/1")
      count_file="$FIXTURE_DIR/current-pr-count"; count=0
      [[ -f "$count_file" ]] && count="$(cat "$count_file")"
      count=$((count + 1)); printf '%s' "$count" >"$count_file"
      if [[ "$FIXTURE_MODE" == "head-change-after-listing" && "$count" -ge 2 ]]; then pr_json "head-b"; else pr_json "head-a"; fi ;;
    "repos/xXKillerNoobYT/Weird-Part-Run-2/commits/head-a/check-runs"|"repos/xXKillerNoobYT/Weird-Part-Run-2/commits/head-b/check-runs")
      jq -nc '{check_runs:[]}' ;;
    "repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/1/reviews?per_page=100")
      [[ "$FIXTURE_MODE" == "review-api-failure" ]] && exit 1
      reviews_json "head-a" ;;
    *) echo "unexpected gh api endpoint: $endpoint ($*)" >&2; exit 1 ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  printf '%q ' "$@" >>"$FIXTURE_DIR/merge.log"; printf '\n' >>"$FIXTURE_DIR/merge.log"; exit 0
fi
echo "unexpected gh invocation: $*" >&2; exit 1
GH
chmod +x "$TMPDIR/gh"

run_rejection_case() {
  local mode="$1" expected="$2" fixture_dir="$TMPDIR/$1" output
  mkdir -p "$fixture_dir"
  output="$(PATH="$TMPDIR:$PATH" FIXTURE_MODE="$mode" FIXTURE_DIR="$fixture_dir" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  printf '%s\n' "$output" | grep -Fq "$expected"
  test ! -s "$fixture_dir/merge.log"
}

# List data says head-listed; first fresh read binds head-a. The final read sees
# head-b and must defer before an invocation is offered.
run_rejection_case "head-change-after-listing" "head changed during final verification"
run_rejection_case "review-api-failure" "could not read review evidence"
run_rejection_case "review-thread-api-failure" "could not read review thread state"
run_rejection_case "unresolved-review-thread" "review threads are unresolved"
# The newer submitted GPTReviewer Revise must supersede its earlier valid pass.
run_rejection_case "later-gpt-revise" "latest current-head review lane rejected (LocalFirst=PASS GPT=REVISE Claude=PASS Copilot=1)"

fixture_dir="$TMPDIR/merge-eligible"; mkdir -p "$fixture_dir"
PATH="$TMPDIR:$PATH" FIXTURE_MODE="merge-eligible" FIXTURE_DIR="$fixture_dir" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 >/dev/null
grep -Fq -- '--match-head-commit head-a' "$fixture_dir/merge.log"

echo "pr-merge-maintenance review-gate regression passed"
