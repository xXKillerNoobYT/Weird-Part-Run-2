#!/usr/bin/env bash
# Deterministic regression: a BLOCKED PR is skipped without consuming the
# one-action budget, allowing a later eligible PR to be selected by either
# merge-maintenance entry point.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

log="${GH_MOCK_LOG:?GH_MOCK_LOG is required}"
command=("$@")

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  cat <<'JSON'
[
  {"number":101,"title":"Blocked candidate","isDraft":false,"labels":[],"author":{"login":"xXKillerNoobYT"},"headRepositoryOwner":{"login":"xXKillerNoobYT"},"headRefName":"fix/blocked","headRefOid":"blocked-sha","mergeStateStatus":"BLOCKED","mergeable":"MERGEABLE","reviewDecision":"APPROVED","autoMergeRequest":null},
  {"number":102,"title":"Clean candidate","isDraft":false,"labels":[],"author":{"login":"xXKillerNoobYT"},"headRepositoryOwner":{"login":"xXKillerNoobYT"},"headRefName":"fix/clean","headRefOid":"clean-sha","mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","reviewDecision":"APPROVED","autoMergeRequest":null}
]
JSON
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "merge" ]]; then
  printf 'merge %s\n' "${3:-}" >>"$log"
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  if [[ " $* " == *" actions/runs?status=action_required "* ]]; then
    exit 0
  fi

  if [[ " $* " == *" --paginate "* && " $* " == *" --slurp "* ]]; then
    cat <<'JSON'
[[
  {"number":101,"title":"Blocked candidate","draft":false,"labels":[],"user":{"login":"xXKillerNoobYT"},"head":{"repo":{"owner":{"login":"xXKillerNoobYT"}},"sha":"blocked-sha"},"mergeable":true,"mergeable_state":"blocked","auto_merge":null},
  {"number":102,"title":"Clean candidate","draft":false,"labels":[],"user":{"login":"xXKillerNoobYT"},"head":{"repo":{"owner":{"login":"xXKillerNoobYT"}},"sha":"clean-sha"},"mergeable":true,"mergeable_state":"clean","auto_merge":null}
]]
JSON
    exit 0
  fi

  if [[ " $* " == *" /issues/"*"/comments?per_page=100 "* ]]; then
    printf '[]\n'
    exit 0
  fi

  if [[ " $* " == *" /check-runs"* ]]; then
    printf '0\n'
    exit 0
  fi
fi

printf 'unexpected gh invocation: %q ' "${command[@]}" >&2
printf '\n' >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

export PATH="$TMPDIR:$PATH"
export GH_MOCK_LOG="$TMPDIR/gh.log"
export APPROVED_PR_AUTOFIX_DRY_RUN=0
export APPROVED_PR_AUTOFIX_VALIDATE=none
export PR_MAINTENANCE_DRY_RUN=0

assert_later_clean_pr_merged() {
  local script_name="$1" output="$2"
  grep -Fq 'merge 102' "$GH_MOCK_LOG"
  ! grep -Fq 'merge 101' "$GH_MOCK_LOG"
  grep -Fq 'BLOCKED' <<<"$output"
  : >"$GH_MOCK_LOG"
  echo "$script_name BLOCKED regression passed"
}

autofix_output="$($ROOT/scripts/approved-pr-autofix.sh xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
assert_later_clean_pr_merged 'approved-pr-autofix' "$autofix_output"

maintenance_output="$($ROOT/scripts/pr-merge-maintenance.sh xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
assert_later_clean_pr_merged 'pr-merge-maintenance' "$maintenance_output"

echo 'BLOCKED merge guard regression passed'
