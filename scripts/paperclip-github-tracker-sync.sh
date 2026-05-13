#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/paperclip-github-tracker-sync.sh [--repo owner/repo] [--tracker-number n] [--state-dir path]
  scripts/paperclip-github-tracker-sync.sh [owner/repo] [tracker-number] [state-dir]

Examples:
  scripts/paperclip-github-tracker-sync.sh
  scripts/paperclip-github-tracker-sync.sh --repo xXKillerNoobYT/Weird-Part-Run-2
  scripts/paperclip-github-tracker-sync.sh xXKillerNoobYT/Weird-Part-Run-2 372 .paperclip-sync
  scripts/paperclip-github-tracker-sync.sh --dry-run

Environment:
  PAPERCLIP_API_URL       Required. Example: http://127.0.0.1:3100
  PAPERCLIP_API_KEY       Required.
  PAPERCLIP_COMPANY_ID    Required.
  PAPERCLIP_WEB_URL       Optional. Used for issue links in the tracker comment.
  GITHUB_REPO             Optional default repo (owner/repo).
  GITHUB_TRACKER_ISSUE    Optional default issue number.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DRY_RUN=0
REPO_ARG=""
TRACKER_NUMBER_ARG=""
STATE_DIR_ARG=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --repo)
      REPO_ARG="${2:?error: --repo requires owner/repo}"
      shift 2
      ;;
    --tracker-number)
      TRACKER_NUMBER_ARG="${2:?error: --tracker-number requires a number}"
      shift 2
      ;;
    --state-dir)
      STATE_DIR_ARG="${2:?error: --state-dir requires a path}"
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

for cmd in curl jq sha256sum gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command missing: $cmd" >&2
    exit 1
  fi
done

: "${PAPERCLIP_API_URL:?error: PAPERCLIP_API_URL is required}"
: "${PAPERCLIP_API_KEY:?error: PAPERCLIP_API_KEY is required}"
: "${PAPERCLIP_COMPANY_ID:?error: PAPERCLIP_COMPANY_ID is required}"

REPO="${REPO_ARG:-${POSITIONAL[0]:-${GITHUB_REPO:-xXKillerNoobYT/Weird-Part-Run-2}}}"
TRACKER_NUMBER="${TRACKER_NUMBER_ARG:-${POSITIONAL[1]:-${GITHUB_TRACKER_ISSUE:-372}}}"
STATE_DIR="${STATE_DIR_ARG:-${POSITIONAL[2]:-.paperclip-sync}}"
STATE_PATH="$STATE_DIR/tracker-${TRACKER_NUMBER}.sha256"
mkdir -p "$STATE_DIR"

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '$REPO'" >&2
  exit 1
fi
if [[ ! "$TRACKER_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: tracker number must be numeric, got '$TRACKER_NUMBER'" >&2
  exit 1
fi

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WEB_URL="${PAPERCLIP_WEB_URL:-}"
ISSUES_PATH="$(mktemp)"
DONE_ISSUES_PATH="$(mktemp)"
AGENTS_PATH="$(mktemp)"
trap 'rm -f "$ISSUES_PATH" "$DONE_ISSUES_PATH" "$AGENTS_PATH"' EXIT

curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues?status=todo,in_progress,in_review,blocked" \
  -o "$ISSUES_PATH"

curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues?status=done" \
  -o "$DONE_ISSUES_PATH"

curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/agents" \
  -o "$AGENTS_PATH"

render_link() {
  local identifier="$1"
  if [[ -n "$WEB_URL" ]]; then
    local prefix="${identifier%%-*}"
    printf "[%s](%s/%s/issues/%s)" "$identifier" "$WEB_URL" "$prefix" "$identifier"
  else
    printf "%s" "$identifier"
  fi
}

COMMENT_BODY="$(
  jq -nr \
    --slurpfile issues "$ISSUES_PATH" \
    --slurpfile doneIssues "$DONE_ISSUES_PATH" \
    --slurpfile agents "$AGENTS_PATH" \
    --arg stamp "$STAMP" '
    def agent_name($id):
      ($agents[0] | map(select(.id == $id)) | .[0].name) // "unassigned";

    def issue_sort_key: .identifier // .id // "";

    def normalized:
      $issues[0]
      | map({
          identifier,
          title,
          status,
          priority,
          assigneeAgentId,
          blockedByIssueIds: (
            (.blockedByIssueIds // [])
            + ((.blockedBy // []) | map(.id))
          ) | unique | sort
        })
      | sort_by(issue_sort_key);

    def recently_completed:
      $doneIssues[0]
      | map({
          identifier,
          title,
          status,
          priority,
          assigneeAgentId,
          completedAt,
          updatedAt
        })
      | sort_by(.completedAt // .updatedAt // "")
      | reverse
      | .[:20];

    def blocker_summary($issue):
      if (($issue.blockedByIssueIds // []) | length) == 0 then "none"
      else (($issue.blockedByIssueIds // []) | join(", "))
      end;

    "# paperclip-tracker-sync:v1\n" +
    "## Paperclip Active Issues Snapshot\n\n" +
    "- Synced at (UTC): `" + $stamp + "`\n" +
    "- Active statuses: `todo`, `in_progress`, `in_review`, `blocked`\n" +
    "- Issue count: `" + ((normalized | length) | tostring) + "`\n\n" +
    "### Active Issues\n\n" +
    (
      (normalized | map(
        "- " + (.identifier // .id) +
        " | **" + (.status // "unknown") + "**" +
        " | owner: `" + (agent_name(.assigneeAgentId)) + "`" +
        " | blockers: `" + blocker_summary(.) + "`" +
        " | " + (.title // "(untitled)")
      )) | join("\n")
    ) + "\n\n" +
    "### Recently Completed\n\n" +
    (
      (recently_completed | map(
        "- " + (.identifier // .id) +
        " | completed: `" + (.completedAt // .updatedAt // "unknown") + "`" +
        " | owner: `" + (agent_name(.assigneeAgentId)) + "`" +
        " | " + (.title // "(untitled)")
      )) | join("\n")
    ) + "\n"
  '
)"

SYNC_FINGERPRINT="$(
  jq -cS -n \
    --slurpfile issues "$ISSUES_PATH" \
    --slurpfile doneIssues "$DONE_ISSUES_PATH" '
    {
      active: (
        $issues[0]
        | map({
            identifier,
            title,
            status,
            priority,
            assigneeAgentId,
            blockedByIssueIds: (
              (.blockedByIssueIds // [])
              + ((.blockedBy // []) | map(.id))
            ) | unique | sort
          })
        | sort_by(.identifier // .id // "")
      ),
      recentlyCompleted: (
        $doneIssues[0]
        | map({
            identifier,
            title,
            status,
            priority,
            assigneeAgentId,
            completedAt,
            updatedAt
          })
        | sort_by(.completedAt // .updatedAt // "")
        | reverse
        | .[:20]
      )
    }
  '
)"

# Convert bare identifiers in bullet lines to markdown links when WEB URL is present.
if [[ -n "$WEB_URL" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^-\ ([A-Z]+-[0-9]+)\ \| ]]; then
      id="${BASH_REMATCH[1]}"
      linked="$(render_link "$id")"
      COMMENT_BODY="${COMMENT_BODY/- $id |/- $linked |}"
    fi
  done < <(printf "%s\n" "$COMMENT_BODY")
fi

CONTENT_HASH="$(printf "%s" "$SYNC_FINGERPRINT" | sha256sum | awk '{print $1}')"
PREV_HASH=""
if [[ -f "$STATE_PATH" ]]; then
  PREV_HASH="$(cat "$STATE_PATH")"
fi

if [[ "$CONTENT_HASH" == "$PREV_HASH" ]]; then
  echo "no material changes detected; tracker update skipped"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: would update $REPO#$TRACKER_NUMBER"
  printf "%s\n" "$COMMENT_BODY"
  exit 0
fi

COMMENTS_JSON="$(gh api "repos/$REPO/issues/$TRACKER_NUMBER/comments?per_page=100")"
EXISTING_ID="$(
  jq -r '
    map(select(.body | startswith("# paperclip-tracker-sync:v1"))) |
    sort_by(.updated_at) |
    last |
    .id // empty
  ' <<<"$COMMENTS_JSON"
)"

if [[ -n "$EXISTING_ID" ]]; then
  gh api \
    --method PATCH \
    "repos/$REPO/issues/comments/$EXISTING_ID" \
    -f "body=$COMMENT_BODY" >/dev/null
  echo "updated tracker comment id: $EXISTING_ID"
else
  gh issue comment "$TRACKER_NUMBER" --repo "$REPO" --body "$COMMENT_BODY" >/dev/null
  echo "created tracker comment on $REPO#$TRACKER_NUMBER"
fi

printf "%s" "$CONTENT_HASH" > "$STATE_PATH"
echo "saved sync hash: $STATE_PATH"
