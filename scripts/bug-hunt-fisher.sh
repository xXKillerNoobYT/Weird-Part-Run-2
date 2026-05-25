#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bug-hunt-fisher.sh [--repo-root path] [--smoke-check]

Description:
  Canonical bug-hunt/fisher entrypoint. Uses plans in docs/plans/ and fails
  fast when required plan files are missing.

Issue selection order:
  blocked -> todo -> backlog
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$DEFAULT_REPO_ROOT"
SMOKE_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="${2:?error: --repo-root requires a path}"
      shift 2
      ;;
    --smoke-check)
      SMOKE_CHECK=1
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "error: unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CORE_PLAN="$REPO_ROOT/docs/plans/hunt-fix-verify-loop.md"
FISHING_PLAN="$REPO_ROOT/docs/plans/master-issue-list.md"
DAILY_TEMPLATE="$REPO_ROOT/docs/hunt-fix-tracker.md"

missing=0
for plan_file in "$CORE_PLAN" "$FISHING_PLAN" "$DAILY_TEMPLATE"; do
  if [[ ! -f "$plan_file" ]]; then
    echo "error: required plan file missing: $plan_file" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

if [[ "$SMOKE_CHECK" -eq 1 ]]; then
  echo "bug-hunt fisher smoke-check passed"
  exit 0
fi

echo "Bug-hunt fisher canonical plans:"
echo "- Core plan: $CORE_PLAN"
echo "- Fishing plan: $FISHING_PLAN"
echo "- Daily template: $DAILY_TEMPLATE"
echo
echo "Issue selection order:"
echo "1. blocked"
echo "2. todo"
echo "3. backlog"
