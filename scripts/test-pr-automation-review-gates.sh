#!/usr/bin/env bash
# Deterministic fixture regression for the two trusted first-party merge paths.
# Proves neither path reaches its dry-run merge command without a submitted
# Copilot review and zero unresolved review threads; autofix also requires an
# explicit APPROVED review decision.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" ]]; then
  shift
  if [[ "${1:-}" == "graphql" ]]; then
    case "${GATE_FIXTURE:?}" in
      missing)
        printf '%s\n' '{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[]},"reviewThreads":{"totalCount":0,"nodes":[]}}}}}'
        ;;
      unresolved)
        printf '%s\n' '{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"state":"COMMENTED","commit":{"oid":"fixture-sha"}}]},"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":false}]}}}}}'
        ;;
      satisfied|stale)
        printf '%s\n' '{"data":{"repository":{"pullRequest":{"latestReviews":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit":{"oid":"fixture-sha"}}]},"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":true}]}}}}}'
        ;;
    esac
    exit 0
  fi

  for arg in "$@"; do
    case "$arg" in
      repos/*/pulls\?state=open*)
        printf '%s\n' '[[{"number":77,"title":"Fixture PR","draft":false,"labels":[],"user":{"login":"xXKillerNoobYT"},"head":{"repo":{"owner":{"login":"xXKillerNoobYT"}},"sha":"fixture-sha"},"mergeable":true,"mergeable_state":"clean","auto_merge":null}]]'
        exit 0
        ;;
      repos/*/commits/*/check-runs*)
        # Both scripts request a jq length through gh; a clean fixture has zero.
        printf '%s\n' '0'
        exit 0
        ;;
      repos/*/pulls/77)
        if [[ "$*" == *'.head.sha // empty'* ]]; then
          if [[ "${GATE_FIXTURE:?}" == "stale" ]]; then
            printf '%s\n' 'newer-sha'
          else
            printf '%s\n' 'fixture-sha'
          fi
        else
          # Missing-Copilot fixture is already awaiting the reviewer, so neither
          # script needs a mutating reviewer-request API call.
          printf '%s\n' '1'
        fi
        exit 0
        ;;
    esac
  done
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  review_decision="APPROVED"
  [[ "${APPROVAL_FIXTURE:-approved}" == "missing" ]] && review_decision="CHANGES_REQUESTED"
  printf '%s\n' "[{\"number\":77,\"title\":\"Fixture PR\",\"isDraft\":false,\"labels\":[],\"author\":{\"login\":\"xXKillerNoobYT\"},\"headRepositoryOwner\":{\"login\":\"xXKillerNoobYT\"},\"headRefName\":\"fixture-branch\",\"headRefOid\":\"fixture-sha\",\"mergeStateStatus\":\"CLEAN\",\"mergeable\":\"MERGEABLE\",\"reviewDecision\":\"$review_decision\",\"autoMergeRequest\":null}]"
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
GH
chmod +x "$TMPDIR/gh"

export PATH="$TMPDIR:$PATH"

assert_gate() {
  local script="$1" fixture="$2" expected="$3" output
  if [[ "$script" == "pr-merge-maintenance.sh" ]]; then
    output="$(GATE_FIXTURE="$fixture" PR_MAINTENANCE_DRY_RUN=1 PR_MAINTENANCE_REQUIRE_COPILOT_REVIEW=0 "$ROOT/scripts/$script" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  else
    output="$(GATE_FIXTURE="$fixture" APPROVED_PR_AUTOFIX_DRY_RUN=1 APPROVED_PR_AUTOFIX_REQUIRE_APPROVAL=0 APPROVED_PR_AUTOFIX_VALIDATE=none "$ROOT/scripts/$script" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
  fi

  printf '%s\n' "$output" | grep -Fq "$expected"
  if [[ "$fixture" == "satisfied" ]]; then
    printf '%s\n' "$output" | grep -Fq 'dry-run: gh pr merge 77'
  else
    if [[ "$fixture" == "stale" ]]; then
      printf '%s\n' "$output" | grep -Fq 'PR head changed from fixture- to newer-sh'
    fi
    if printf '%s\n' "$output" | grep -Fq 'dry-run: gh pr merge 77'; then
      echo "$script unexpectedly reached merge for $fixture gate fixture" >&2
      exit 1
    fi
  fi
}

for script in pr-merge-maintenance.sh approved-pr-autofix.sh; do
  assert_gate "$script" missing 'Copilot review pending'
  assert_gate "$script" unresolved 'unresolved review thread(s)'
  assert_gate "$script" stale 'PR head changed from fixture- to newer-sh'
  assert_gate "$script" satisfied 'dry-run: gh pr merge 77'
done

approval_output="$(GATE_FIXTURE=satisfied APPROVAL_FIXTURE=missing APPROVED_PR_AUTOFIX_DRY_RUN=1 APPROVED_PR_AUTOFIX_REQUIRE_APPROVAL=0 APPROVED_PR_AUTOFIX_VALIDATE=none "$ROOT/scripts/approved-pr-autofix.sh" xXKillerNoobYT/Weird-Part-Run-2 2>&1)"
printf '%s\n' "$approval_output" | grep -Fq 'bounded autofix requires an APPROVED GitHub review'
if printf '%s\n' "$approval_output" | grep -Fq 'dry-run: gh pr merge 77'; then
  echo "approved-pr-autofix.sh unexpectedly reached merge without approval" >&2
  exit 1
fi

echo "pr automation review-gate regression passed"
