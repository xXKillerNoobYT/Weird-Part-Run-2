#!/usr/bin/env bash
# Deterministic regression for post-evidence fetch drift in both repair paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
CALL_LOG="$TMPDIR/calls.log"

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  if [[ "${REPAIR_MODE:?}" == "merge-conflict" ]]; then
    mergeable="CONFLICTING"
    merge_state="DIRTY"
  else
    mergeable="MERGEABLE"
    merge_state="CLEAN"
  fi
  printf '%s\n' "{\"number\":77,\"title\":\"Fixture PR\",\"isDraft\":false,\"labels\":[],\"author\":{\"login\":\"xXKillerNoobYT\"},\"headRepositoryOwner\":{\"login\":\"xXKillerNoobYT\"},\"headRefName\":\"fixture-branch\",\"headRefOid\":\"fixture-sha\",\"mergeStateStatus\":\"$merge_state\",\"mergeable\":\"$mergeable\",\"reviewDecision\":\"APPROVED\",\"autoMergeRequest\":null}"
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  printf '%s\n' 'gh pr comment' >>"${CALL_LOG:?}"
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ "${1:-}" == "graphql" ]]; then
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit":{"oid":"fixture-sha"}}]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}'
    exit 0
  fi
  for arg in "$@"; do
    case "$arg" in
      repos/*/issues/77/comments?per_page=100)
        printf '%s\n' '[]'
        exit 0
        ;;
      repos/*/pulls/77)
        printf '%s\n' 'fixture-sha'
        exit 0
        ;;
      repos/*/commits/fixture-sha/check-runs?per_page=100)
        if [[ "$*" == *'in_progress'* ]]; then
          printf '%s\n' '0'
        else
          printf '%s\n' '1'
        fi
        exit 0
        ;;
    esac
  done
fi

echo "unexpected gh invocation: $*" >&2
exit 1
GH

cat >"$TMPDIR/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"${CALL_LOG:?}"
case "${1:-}" in
  fetch) exit 0 ;;
  rev-parse)
    # The remote source branch moves after review/check evidence is collected.
    printf '%s\n' 'newer-sha'
    exit 0
    ;;
esac
echo "unexpected git invocation after repair-head drift: $*" >&2
exit 1
GIT

cat >"$TMPDIR/codex" <<'CODEX'
#!/usr/bin/env bash
printf 'codex %s\n' "$*" >>"${CALL_LOG:?}"
echo 'Codex must not run after repair-head drift' >&2
exit 1
CODEX

chmod +x "$TMPDIR/gh" "$TMPDIR/git" "$TMPDIR/codex"
export PATH="$TMPDIR:$PATH"
export CALL_LOG

assert_drift_stops_repair() {
  local mode="$1" output
  : >"$CALL_LOG"
  output="$(REPAIR_MODE="$mode" APPROVED_PR_AUTOFIX_PR_NUMBER=77 APPROVED_PR_AUTOFIX_REQUIRE_APPROVAL=1 APPROVED_PR_AUTOFIX_VALIDATE=none "$ROOT/scripts/approved-pr-autofix.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  printf '%s\n' "$output" | grep -Fq 'fetched PR branch head changed from fixture- to newer-sh before'
  grep -Fq 'git fetch origin main fixture-branch' "$CALL_LOG"
  grep -Fq 'git rev-parse origin/fixture-branch' "$CALL_LOG"
  if grep -Eq '^(codex |git (checkout|reset|merge|add|commit|push))' "$CALL_LOG"; then
    echo "$mode repair unexpectedly continued after fetched-head drift:" >&2
    cat "$CALL_LOG" >&2
    exit 1
  fi
}

assert_drift_stops_repair merge-conflict
assert_drift_stops_repair failing-checks

echo "approved-pr-autofix repair-head-drift regression passed"
