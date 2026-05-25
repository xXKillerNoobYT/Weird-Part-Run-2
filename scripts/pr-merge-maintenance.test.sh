#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/home/runner/work/Weird-Part-Run-2/Weird-Part-Run-2"
SCRIPT="$REPO_ROOT/scripts/pr-merge-maintenance.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "expected output to contain: $needle" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "expected output to NOT contain: $needle" >&2
    return 1
  fi
}

run_case() {
  local merge_error="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  cat > "$tmp_dir/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  cat <<'JSON'
[{"number":42,"title":"Fix test","isDraft":false,"labels":[],"headRepositoryOwner":{"login":"owner"},"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","autoMergeRequest":null}]
JSON
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
  echo "$MOCK_MERGE_ERROR" >&2
  exit 1
fi
echo "unexpected gh args: $*" >&2
exit 1
GH
  chmod +x "$tmp_dir/gh"

  local output
  output="$(PATH="$tmp_dir:$PATH" MOCK_MERGE_ERROR="$merge_error" "$SCRIPT" owner/repo 2>&1 || true)"
  printf '%s' "$output"
}

approval_output="$(run_case 'GraphQL: At least 1 approving review is required by reviewers with write access.')"
assert_contains "$approval_output" "blocked: merge approval required from non-author maintainer"
assert_contains "$approval_output" "merge gate backlog detected (1 PRs need non-author approval)."
assert_contains "$approval_output" "- #42 Fix test"

generic_output="$(run_case 'GraphQL: failed to enable auto-merge')"
assert_contains "$generic_output" "blocked: auto-merge enable failed"
assert_not_contains "$generic_output" "merge gate backlog detected"

echo "pr-merge-maintenance tests passed"
