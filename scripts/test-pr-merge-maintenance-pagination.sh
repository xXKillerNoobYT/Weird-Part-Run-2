#!/usr/bin/env bash
# Canonical regression for pr-merge-maintenance queue pagination and explicit caps.
# This supersedes the legacy tests/pr-merge-maintenance-scan-counts.sh mock, which
# exercised the pre-REST-pagination `gh pr list` implementation removed by #1061.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" ]]; then
  shift
  has_paginate=0
  has_slurp=0
  endpoint=""
  for arg in "$@"; do
    case "$arg" in
      --paginate) has_paginate=1 ;;
      --slurp) has_slurp=1 ;;
      repos/*) endpoint="$arg" ;;
    esac
  done
  if [[ "$endpoint" =~ ^repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/[0-9]+$ ]]; then
    number="${endpoint##*/}"
    python3 - "$number" <<'PY'
import json, sys
n = int(sys.argv[1])
print(json.dumps({
    "number": n,
    "title": f"Mock PR {n}",
    "draft": True,
    "labels": [],
    "user": {"login": "xXKillerNoobYT"},
    "head": {"repo": {"owner": {"login": "xXKillerNoobYT"}}, "sha": ""},
    "mergeable": None,
    "mergeable_state": "unknown",
    "auto_merge": None,
}))
PY
    exit 0
  fi
  if [[ "$has_paginate" -ne 1 || "$has_slurp" -ne 1 ]]; then
    echo "expected gh api invocation to include --paginate and --slurp: $*" >&2
    exit 1
  fi
  if [[ "$endpoint" != "repos/xXKillerNoobYT/Weird-Part-Run-2/pulls?state=open&base=main&per_page=100" ]]; then
    echo "unexpected gh api endpoint: $endpoint" >&2
    exit 1
  fi
  python3 - <<'PY'
import json
# Simulate two REST pages after `gh api --paginate --slurp`. The first page is
# full at the runtime's per_page=100 contract so both full-queue and capped runs
# must flatten across the page boundary.
# The script transforms these fields; use realistic shapes to exercise the jq.
prs = [{
    "number": n,
    "title": f"Mock PR {n}",
    "draft": True,
    "labels": [],
    "head": {"repo": {"owner": {"login": "xXKillerNoobYT"}}, "sha": ""},
    "mergeable": None,
    "mergeable_state": "unknown",
    "auto_merge": None,
} for n in range(1, 126)]
print(json.dumps([prs[:100], prs[100:]]))
PY
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

export PATH="$TMPDIR:$PATH"
export PR_MAINTENANCE_DRY_RUN=1
unset PR_MAINTENANCE_MAX_PRS

full_output="$($ROOT/scripts/pr-merge-maintenance.sh xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
printf '%s\n' "$full_output" | grep -q 'Found 125 open PR(s); inspecting 125.'
full_count="$(printf '%s\n' "$full_output" | grep -c '^--- PR #')"
test "$full_count" -eq 125

export PR_MAINTENANCE_MAX_PRS=105
capped_output="$($ROOT/scripts/pr-merge-maintenance.sh xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
printf '%s\n' "$capped_output" | grep -q 'Found 125 open PR(s); inspecting 105.'
printf '%s\n' "$capped_output" | grep -q 'warning: explicit PR_MAINTENANCE_MAX_PRS=105 limits this run to 105 of 125 open PRs'
capped_count="$(printf '%s\n' "$capped_output" | grep -c '^--- PR #')"
test "$capped_count" -eq 105

echo "pr-merge-maintenance pagination regression passed"
