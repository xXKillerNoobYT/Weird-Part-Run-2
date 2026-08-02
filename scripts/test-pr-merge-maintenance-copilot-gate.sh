#!/usr/bin/env bash
# Deterministic regression for the serialized merge's exact-head Copilot gate.
# Cases cover absent/stale/current evidence, trusted-ledger waivers, unknown
# review state, and owner attribution for referenced approval comments.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

log="${GH_MOCK_LOG:?GH_MOCK_LOG is required}"
{ printf 'call:'; printf ' %q' "$@"; printf '\n'; } >>"$log"
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
if [[ "$*" == *"contents/.github/merge-control/copilot-review-waivers.json?ref=main"* ]]; then
  cat "${GH_TRUSTED_WAIVER_FIXTURE:?GH_TRUSTED_WAIVER_FIXTURE is required}"
  exit 0
fi
if [[ "$*" == *"/issues/comments/123"* ]]; then
  cat "${GH_APPROVAL_FIXTURE:?GH_APPROVAL_FIXTURE is required}"
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
{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer"},"state":"APPROVED","commit":{"oid":"prior-head-sha"}}]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}
JSON
cat >"$TMPDIR/current.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer"},"state":"COMMENTED","commit":{"oid":"head-sha"}}]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}
JSON
: >"$TMPDIR/unreadable.json"
cat >"$TMPDIR/empty-waivers.json" <<'JSON'
{"version":1,"waivers":[]}
JSON
cat >"$TMPDIR/valid-waiver.json" <<'JSON'
{"version":1,"waivers":[{"pr":101,"head_sha":"head-sha","approved_by":"xXKillerNoobYT","reason":"Documented incident exception","approval_url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/101#issuecomment-123"}]}
JSON
cat >"$TMPDIR/owner-comment.json" <<'JSON'
{"user":{"login":"xXKillerNoobYT"},"issue_url":"https://api.github.com/repos/xXKillerNoobYT/Weird-Part-Run-2/issues/101"}
JSON
cat >"$TMPDIR/non-owner-comment.json" <<'JSON'
{"user":{"login":"not-the-owner"},"issue_url":"https://api.github.com/repos/xXKillerNoobYT/Weird-Part-Run-2/issues/101"}
JSON

export PATH="$TMPDIR:$PATH"
export GH_MOCK_LOG="$TMPDIR/gh.log"
export PR_MAINTENANCE_DRY_RUN=0

run_case() {
  local name="$1" review_fixture="$2" trusted_waiver_fixture="$3" approval_fixture="$4" expect_merge="$5" expected_message="$6"
  : >"$GH_MOCK_LOG"
  output="$(GH_REVIEW_FIXTURE="$review_fixture" GH_TRUSTED_WAIVER_FIXTURE="$trusted_waiver_fixture" GH_APPROVAL_FIXTURE="$approval_fixture" "$ROOT/scripts/pr-merge-maintenance.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  if ! grep -Fq "$expected_message" <<<"$output"; then
    printf 'expected message missing: %s\noutput:\n%s\ngh calls:\n' "$expected_message" "$output" >&2
    cat "$GH_MOCK_LOG" >&2
    return 1
  fi
  if [[ "$expect_merge" == "yes" ]]; then
    grep -Fq 'merge 101' "$GH_MOCK_LOG"
  else
    ! grep -Fq 'merge 101' "$GH_MOCK_LOG"
  fi
  echo "$name passed"
}

run_case 'missing exact-head evidence denies' "$TMPDIR/missing.json" "$TMPDIR/empty-waivers.json" "$TMPDIR/owner-comment.json" no 'no exact-head Copilot review or valid waiver'
run_case 'stale-head evidence denies' "$TMPDIR/stale.json" "$TMPDIR/empty-waivers.json" "$TMPDIR/owner-comment.json" no 'no exact-head Copilot review or valid waiver'
run_case 'current-head live Copilot identity allows' "$TMPDIR/current.json" "$TMPDIR/empty-waivers.json" "$TMPDIR/owner-comment.json" yes 'submitted exact-head review(s) found'
run_case 'trusted PR-and-SHA owner waiver allows' "$TMPDIR/missing.json" "$TMPDIR/valid-waiver.json" "$TMPDIR/owner-comment.json" yes 'owner-approved exact PR-and-SHA waiver found in trusted main ledger'
run_case 'unreadable review state denies despite waiver' "$TMPDIR/unreadable.json" "$TMPDIR/valid-waiver.json" "$TMPDIR/owner-comment.json" no 'could not read Copilot review state'
run_case 'non-owner waiver approval comment denies' "$TMPDIR/missing.json" "$TMPDIR/valid-waiver.json" "$TMPDIR/non-owner-comment.json" no 'waiver approval comment is not an owner comment'

# An arbitrary workflow checkout file must not influence the decision: only the
# base branch API response above is consulted by the maintainer.
PR_MAINTENANCE_COPILOT_WAIVER_FILE="$TMPDIR/valid-waiver.json" \
  run_case 'untrusted-ref ledger is ignored' "$TMPDIR/missing.json" "$TMPDIR/empty-waivers.json" "$TMPDIR/owner-comment.json" no 'no exact-head Copilot review or valid waiver'

echo 'Copilot exact-head merge gate regression passed'
