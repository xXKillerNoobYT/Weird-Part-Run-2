#!/usr/bin/env bash
# Verifies pr-merge-maintenance inspects the full open PR queue by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "api" ]]; then
  python3 - <<'PY'
import json
print(json.dumps([[{"number": n} for n in range(1, 56)]]))
PY
  exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  number="$3"
  python3 - "$number" <<'PY'
import json, sys
number = int(sys.argv[1])
print(json.dumps({
    "number": number,
    "title": f"Mock PR {number}",
    "isDraft": True,
    "labels": [],
    "headRepositoryOwner": {"login": "xXKillerNoobYT"},
    "mergeStateStatus": "CLEAN",
    "mergeable": "MERGEABLE",
    "autoMergeRequest": None,
}))
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
printf '%s\n' "$full_output" | grep -q 'Found 55 open PR(s); inspecting 55.'
full_count="$(printf '%s\n' "$full_output" | grep -c '^--- PR #')"
test "$full_count" -eq 55

export PR_MAINTENANCE_MAX_PRS=50
capped_output="$($ROOT/scripts/pr-merge-maintenance.sh xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
printf '%s\n' "$capped_output" | grep -q 'Found 55 open PR(s); inspecting 50.'
printf '%s\n' "$capped_output" | grep -q 'warning: explicit PR_MAINTENANCE_MAX_PRS=50 limits this run to 50 of 55 open PRs'
capped_count="$(printf '%s\n' "$capped_output" | grep -c '^--- PR #')"
test "$capped_count" -eq 50

echo "pr-merge-maintenance pagination regression passed"
