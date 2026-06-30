#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/github-issue-sync.sh [--repo owner/repo] [--output-dir path] [--state open|closed|all] [--source-issue WEI-123]
  scripts/github-issue-sync.sh [owner/repo] [output-dir]

Examples:
  scripts/github-issue-sync.sh
  scripts/github-issue-sync.sh --repo xXKillerNoobYT/Weird-Part-Run-2 --state all --source-issue WEI-4159
  scripts/github-issue-sync.sh xXKillerNoobYT/Weird-Part-Run-2 .tmp/github-issue-sync
EOF
}

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPO_ARG=""
OUT_DIR_ARG=""
STATE_ARG=""
SOURCE_ISSUE_ARG=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ARG="${2:?error: --repo requires owner/repo}"
      shift 2
      ;;
    --output-dir)
      OUT_DIR_ARG="${2:?error: --output-dir requires a path}"
      shift 2
      ;;
    --state)
      STATE_ARG="${2:?error: --state requires open, closed, or all}"
      shift 2
      ;;
    --source-issue)
      SOURCE_ISSUE_ARG="${2:?error: --source-issue requires an issue identifier}"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

REPO="${REPO_ARG:-${POSITIONAL[0]:-${GITHUB_REPO:-xXKillerNoobYT/Weird-Part-Run-2}}}"
OUT_DIR="${OUT_DIR_ARG:-${POSITIONAL[1]:-.tmp/github-issue-sync}}"
ISSUE_STATE="${STATE_ARG:-${GITHUB_ISSUE_SYNC_STATE:-all}}"
SOURCE_ISSUE="${SOURCE_ISSUE_ARG:-${PAPERCLIP_TASK_ID:-${GITHUB_ISSUE_SYNC_SOURCE_ISSUE:-WEI-44}}}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP_DIR="${STAMP//:/-}"
mkdir -p "$OUT_DIR"

if [[ ! "$REPO" =~ ^([^/]+)/([^/]+)$ ]]; then
  echo "error: expected [owner/repo], got '$REPO'" >&2
  usage >&2
  exit 1
fi
if [[ ! "$ISSUE_STATE" =~ ^(open|closed|all)$ ]]; then
  echo "error: --state must be open, closed, or all; got '$ISSUE_STATE'" >&2
  usage >&2
  exit 1
fi
RUN_DIR="$OUT_DIR/$STAMP_DIR"
JSON_PATH="$RUN_DIR/issues.json"
MD_PATH="$RUN_DIR/summary.md"
LATEST_JSON="$OUT_DIR/latest-sync.json"
LATEST_MD="$OUT_DIR/latest-sync.md"
TMP_JSON="$OUT_DIR/.issues-${STAMP_DIR}.json.tmp"

# Pull all repository issues through the paginated REST API and exclude pull requests.
# `gh issue list` defaults to a capped result set; use `gh api --paginate` so
# canonical all-state snapshots cannot silently truncate above 200 issues.
mkdir -p "$RUN_DIR"

gh api \
  --method GET \
  --paginate \
  --slurp \
  -f state="$ISSUE_STATE" \
  -f per_page=100 \
  "repos/$REPO/issues" > "$TMP_JSON"

jq '
  def issue_pages:
    if type == "array" and (length == 0 or (.[0] | type) == "array") then .[] else . end;

  [
    issue_pages[]
    | select(has("pull_request") | not)
    | {
        number,
        title,
        state: (.state | ascii_upcase),
        labels,
        assignees,
        author: .user,
        createdAt: .created_at,
        updatedAt: .updated_at,
        url: .html_url
      }
  ]
' "$TMP_JSON" > "$JSON_PATH"
rm -f "$TMP_JSON"

TOTAL="$(jq 'length' "$JSON_PATH")"
OPEN_TOTAL="$(jq 'map(select(.state == "OPEN")) | length' "$JSON_PATH")"
CLOSED_TOTAL="$(jq 'map(select(.state == "CLOSED")) | length' "$JSON_PATH")"

{
  echo "# GitHub Issue Sync Snapshot"
  echo
  printf -- "- Repository: \`%s\`\n" "$REPO"
  printf -- "- Run timestamp (UTC): \`%s\`\n" "$STAMP"
  printf -- "- Source issue: \`%s\`\n" "$SOURCE_ISSUE"
  printf -- "- Requested state: \`%s\`\n" "$ISSUE_STATE"
  printf -- "- Issues (non-PR): \`%s\`\n" "$TOTAL"
  printf -- "- Open issues: \`%s\`\n" "$OPEN_TOTAL"
  printf -- "- Closed issues: \`%s\`\n" "$CLOSED_TOTAL"
  printf -- "- Raw data: \`%s\`\n" "issues.json"
  echo
  echo "## Top 20 Recently Updated"
  echo
  jq -r '
    sort_by(.updatedAt) | reverse | .[:20] |
    .[] | "- #\(.number) [\(.state)]: \(.title) (updated \(.updatedAt))"' "$JSON_PATH"
} > "$MD_PATH"

jq -n \
  --arg repository "$REPO" \
  --arg runTimestampUtc "$STAMP" \
  --arg sourceIssue "$SOURCE_ISSUE" \
  --arg requestedState "$ISSUE_STATE" \
  --argjson issueCount "$TOTAL" \
  --argjson openCount "$OPEN_TOTAL" \
  --argjson closedCount "$CLOSED_TOTAL" \
  --arg runDir "$RUN_DIR" \
  --slurpfile issues "$JSON_PATH" \
  '{
    repository: $repository,
    runTimestampUtc: $runTimestampUtc,
    sourceIssue: $sourceIssue,
    requestedState: $requestedState,
    openIssueCount: $openCount,
    issueCount: $issueCount,
    openCount: $openCount,
    closedCount: $closedCount,
    runDir: $runDir,
    issues: $issues[0]
  }' > "$LATEST_JSON"

cp "$MD_PATH" "$LATEST_MD"

if [[ ! -s "$LATEST_MD" || ! -s "$LATEST_JSON" ]]; then
  echo "error: canonical artifacts missing or empty" >&2
  exit 1
fi

echo "wrote: $JSON_PATH"
echo "wrote: $MD_PATH"
echo "wrote: $LATEST_JSON"
echo "wrote: $LATEST_MD"
