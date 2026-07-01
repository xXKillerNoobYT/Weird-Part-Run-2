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
# Simulate REST /repos/.../pulls?state=open response (one slurped page).
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
} for n in range(1, 56)]
print(json.dumps([prs]))
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
