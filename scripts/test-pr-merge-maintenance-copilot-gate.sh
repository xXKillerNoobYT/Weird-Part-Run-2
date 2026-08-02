#!/usr/bin/env bash
# Deterministic regression for the serialized merge's exact-head Copilot gate.
# Cases: missing evidence denies, stale-head evidence denies, current-head
# evidence allows, and a tracked owner-approved PR/SHA waiver allows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

log="${GH_MOCK_LOG:?GH_MOCK_LOG is required}"
if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  printf 'merge %s\n' "${3:-}" >>"$log"
  exit 0
fi
if [[ "${1:-}" != "api" ]]; then
  printf 'unexpected gh invocation: %q ' "$@" >&2
  printf '\n' >&2
  exit 1
fi

if [[ " $* " == *" actions/runs?status=action_required "* ]]; then
  exit 0
fi
if [[ " $* " == *" --paginate "* && " $* " == *" --slurp "* ]]; then
  cat <<'JSON'
[[{"number":101,"title":"Clean candidate","draft":false,"labels":[],"user":{"login":"xXKillerNoobYT"},"head":{"repo":{"owner":{"login":"xXKillerNoobYT"}},"sha":"head-sha"},"mergeable":true,"mergeable_state":"clean","auto_merge":null}]]
JSON
  exit 0
fi
if [[ " $* " == *" graphql "* ]]; then
  cat "${GH_REVIEW_FIXTURE:?GH_REVIEW_FIXTURE is required}"
  exit 0
fi
if [[ " $* " == *" /check-runs"* ]]; then
  printf '0\n'
  exit 0
fi
if [[ " $* " == *" requested_reviewers"* ]]; then
  printf 'request-review\n' >>"$log"
  exit 0
fi
if [[ " $* " == *" repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/101 "* ]]; then
  printf '0\n'
  exit 0
fi
printf 'unexpected gh invocation: %q ' "$@" >&2
printf '\n' >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

cat >"$TMPDIR/missing.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}
JSON
cat >"$TMPDIR/stale.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit":{"oid":"prior-head-sha"}}]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}
JSON
cat >"$TMPDIR/current.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"state":"COMMENTED","commit":{"oid":"head-sha"}}]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}
JSON
cat >"$TMPDIR/empty-waivers.json" <<'JSON'
{"version":1,"waivers":[]}
JSON
cat >"$TMPDIR/valid-waiver.json" <<'JSON'
{"version":1,"waivers":[{"pr":101,"head_sha":"head-sha","approved_by":"xXKillerNoobYT","reason":"Documented incident exception","approval_url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/101#issuecomment-123"}]}
JSON

export PATH="$TMPDIR:$PATH"
export GH_MOCK_LOG="$TMPDIR/gh.log"
export PR_MAINTENANCE_DRY_RUN=0

run_case() {
  local name="$1" review_fixture="$2" waiver_file="$3" expect_merge="$4" expected_message="$5"
  : >"$GH_MOCK_LOG"
  output="$(GH_REVIEW_FIXTURE="$review_fixture" PR_MAINTENANCE_COPILOT_WAIVER_FILE="$waiver_file" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  grep -Fq "$expected_message" <<<"$output"
  if [[ "$expect_merge" == "yes" ]]; then
    grep -Fq 'merge 101' "$GH_MOCK_LOG"
  else
    ! grep -Fq 'merge 101' "$GH_MOCK_LOG"
  fi
  echo "$name passed"
}

run_case 'missing exact-head evidence denies' "$TMPDIR/missing.json" "$TMPDIR/empty-waivers.json" no 'no exact-head Copilot review or valid waiver'
run_case 'stale-head evidence denies' "$TMPDIR/stale.json" "$TMPDIR/empty-waivers.json" no 'no exact-head Copilot review or valid waiver'
run_case 'current-head Copilot evidence allows' "$TMPDIR/current.json" "$TMPDIR/empty-waivers.json" yes 'submitted exact-head review(s) found'
run_case 'owner PR-and-SHA waiver allows' "$TMPDIR/missing.json" "$TMPDIR/valid-waiver.json" yes 'owner-approved exact PR-and-SHA waiver found'

echo 'Copilot exact-head merge gate regression passed'
