#!/usr/bin/env bash
# Regression: the merge train must fail closed until every reviewer has an
# accepted review bound to the PR's exact current head.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ " $* " == *" repos/xXKillerNoobYT/Weird-Part-Run-2/pulls?state=open&base=main&per_page=100 "* ]]; then
    cat <<'JSON'
[[{"number":42,"title":"Mock PR","draft":false,"labels":[],"user":{"login":"xXKillerNoobYT"},"head":{"repo":{"owner":{"login":"xXKillerNoobYT"}},"sha":"deadbeef"},"mergeable":true,"mergeable_state":"clean","auto_merge":null}]]
JSON
    exit 0
  fi
  if [[ " $* " == *" repos/xXKillerNoobYT/Weird-Part-Run-2/commits/deadbeef/check-runs "* ]]; then
    printf '%s\n' '{"check_runs":[]}'
    exit 0
  fi
  if [[ " $* " == *" repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/42/reviews?per_page=100 "* ]]; then
    printf '[%s]\n' "$MOCK_REVIEWS"
    exit 0
  fi
  if [[ " $* " == *" graphql "* ]]; then
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":0,"nodes":[]}}}}}'
    exit 0
  fi
fi

echo "unexpected gh invocation: $*" >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

export PATH="$TMPDIR:$PATH"
export PR_MAINTENANCE_DRY_RUN=1

missing_reviews='[{"commit_id":"deadbeef","state":"COMMENTED","body":"## LocalFirst exact-head review\nVerdict: Pass","user":{"login":"xXKillerNoobYT"}}]'
stale_reviews='[{"commit_id":"oldhead","state":"COMMENTED","body":"## LocalFirst exact-head review\nVerdict: Pass","user":{"login":"xXKillerNoobYT"}},{"commit_id":"oldhead","state":"COMMENTED","body":"## GPTReviewer exact-head review\nVerdict: Accept","user":{"login":"xXKillerNoobYT"}},{"commit_id":"oldhead","state":"COMMENTED","body":"## ClaudeReviewer final exact-head review\nVerdict: Accept","user":{"login":"xXKillerNoobYT"}},{"commit_id":"oldhead","state":"COMMENTED","body":"Copilot review","user":{"login":"copilot-pull-request-reviewer[bot]"}}]'
complete_reviews='[{"commit_id":"deadbeef","state":"COMMENTED","body":"## LocalFirst exact-head review\nVerdict: Pass","user":{"login":"xXKillerNoobYT"}},{"commit_id":"deadbeef","state":"COMMENTED","body":"## GPTReviewer exact-head review\nVerdict: Accept","user":{"login":"xXKillerNoobYT"}},{"commit_id":"deadbeef","state":"COMMENTED","body":"## ClaudeReviewer final exact-head review\nVerdict: Accept","user":{"login":"xXKillerNoobYT"}},{"commit_id":"deadbeef","state":"COMMENTED","body":"Copilot review","user":{"login":"copilot-pull-request-reviewer[bot]"}}]'

MOCK_REVIEWS="$missing_reviews" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 >"$TMPDIR/missing.log" 2>&1
grep -q 'current-head review lane incomplete' "$TMPDIR/missing.log"
if grep -q 'dry-run: gh pr merge' "$TMPDIR/missing.log"; then
  echo "merge was offered despite missing exact-head review lanes" >&2
  exit 1
fi

MOCK_REVIEWS="$stale_reviews" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 >"$TMPDIR/stale.log" 2>&1
grep -q 'current-head review lane incomplete' "$TMPDIR/stale.log"
if grep -q 'dry-run: gh pr merge' "$TMPDIR/stale.log"; then
  echo "merge was offered using review evidence from an older head" >&2
  exit 1
fi

MOCK_REVIEWS="$complete_reviews" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 >"$TMPDIR/complete.log" 2>&1
grep -q 'current-head review lanes satisfied' "$TMPDIR/complete.log"
grep -q 'dry-run: gh pr merge' "$TMPDIR/complete.log"

echo "pr-merge-maintenance review-gate regression passed"
