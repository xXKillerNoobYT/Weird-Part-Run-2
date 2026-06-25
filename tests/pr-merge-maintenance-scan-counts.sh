#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_CALL_LOG:?}"
if [[ "${1:-}" == "api" ]]; then
  for i in $(seq 1 "${MOCK_OPEN_PR_COUNT:-55}"); do
    echo "$i"
  done
  exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  limit=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--limit" ]]; then
      shift
      limit="$1"
      break
    fi
    shift
  done
  : "${limit:?missing --limit}"
  python3 - "$limit" <<'PY'
import json, sys
limit = int(sys.argv[1])
print(json.dumps([
    {
        "number": i,
        "title": f"Mock PR {i}",
        "isDraft": True,
        "labels": [],
        "headRepositoryOwner": {"login": "xXKillerNoobYT"},
        "mergeStateStatus": "CLEAN",
        "mergeable": "MERGEABLE",
        "autoMergeRequest": None,
    }
    for i in range(1, limit + 1)
]))
PY
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 64
GH
chmod +x "$tmpdir/gh"

export PATH="$tmpdir:$PATH"
export GH_CALL_LOG="$tmpdir/gh-calls.log"
export MOCK_OPEN_PR_COUNT=55

output="$(PR_MAINTENANCE_DRY_RUN=1 "$repo_root/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2)"
[[ "$output" == *"PR scan counts: total_open=55 inspected_limit=55"* ]]
[[ "$output" == *"Found 55 open PR(s); inspecting 55."* ]]
grep -q -- '--limit 55' "$GH_CALL_LOG"

: >"$GH_CALL_LOG"
set +e
capped_output="$(PR_MAINTENANCE_DRY_RUN=1 PR_MAINTENANCE_MAX_PRS=50 "$repo_root/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]]
[[ "$capped_output" == *"incomplete PR scan refused: total_open=55 inspected_limit=50"* ]]
if grep -q '^pr list' "$GH_CALL_LOG"; then
  echo "expected capped incomplete scan to fail before gh pr list" >&2
  exit 1
fi

echo "pr-merge-maintenance scan-count smoke test passed"
