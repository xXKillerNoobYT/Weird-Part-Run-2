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

for cmd in curl jq gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command missing: $cmd" >&2
    exit 1
  fi
done

hash_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -r | awk '{print $1}'
  else
    echo "error: required command missing: sha256sum, shasum, or openssl" >&2
    return 1
  fi
}

: "${PAPERCLIP_API_URL:?error: PAPERCLIP_API_URL is required}"
: "${PAPERCLIP_API_KEY:?error: PAPERCLIP_API_KEY is required}"
: "${PAPERCLIP_COMPANY_ID:?error: PAPERCLIP_COMPANY_ID is required}"

REPO="${REPO_ARG:-${POSITIONAL[0]:-${GITHUB_REPO:-xXKillerNoobYT/Weird-Part-Run-2}}}"
TRACKER_NUMBER="${TRACKER_NUMBER_ARG:-${POSITIONAL[1]:-${GITHUB_TRACKER_ISSUE:-372}}}"
STATE_DIR="${STATE_DIR_ARG:-${POSITIONAL[2]:-.paperclip-sync}}"
STATE_PATH="$STATE_DIR/tracker-${TRACKER_NUMBER}.sha256"
STATE_DATA_PATH="$STATE_DIR/tracker-${TRACKER_NUMBER}.json"
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

ISSUES_JSON="$(curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues?status=todo,in_progress,in_review,blocked")"

AGENTS_JSON="$(curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/agents")"

NORMALIZED_JSON="$(
  jq -cS -n \
    --argjson issues "$ISSUES_JSON" \
    --argjson agents "$AGENTS_JSON" '
    def agent_name($id):
      ($agents | map(select(.id == $id)) | .[0].name) // "unassigned";

    $issues
    | map({
        identifier: (.identifier // (.id | tostring)),
        title: (.title // "(untitled)"),
        status: (.status // "unknown"),
        priority,
        assigneeAgentId,
        assigneeName: agent_name(.assigneeAgentId),
        blockerIds: (
          (.blockedByIssueIds // [] | map(tostring))
          + ((.blockedBy // []) | map(.identifier // .id // tostring))
        ) | unique | sort
      })
    | sort_by(.identifier)
  '
)"

PREV_SYNC_JSON='[]'
if [[ -f "$STATE_DATA_PATH" ]]; then
  if jq -e . "$STATE_DATA_PATH" >/dev/null 2>&1; then
    PREV_SYNC_JSON="$(cat "$STATE_DATA_PATH")"
  fi
fi

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
    --argjson normalized "$NORMALIZED_JSON" \
    --argjson previous "$PREV_SYNC_JSON" \
    --arg stamp "$STAMP" '
    def as_map($arr):
      reduce $arr[] as $item ({}; .[$item.identifier] = $item);

    def blocker_summary($issue):
      if (($issue.blockerIds // []) | length) == 0 then "none"
      else ($issue.blockerIds | join(", "))
      end;

    def status_owner_changes($current; $previous):
      as_map($current) as $curr
      | as_map($previous) as $prev
      | (
          ($current | map(.identifier))
          | map(select($prev[.] != null))
          | map(
              {
                identifier: .,
                oldStatus: ($prev[.].status // "unknown"),
                newStatus: ($curr[.].status // "unknown"),
                oldOwner: ($prev[.].assigneeName // "unassigned"),
                newOwner: ($curr[.].assigneeName // "unassigned")
              }
            )
          | map(select(.oldStatus != .newStatus or .oldOwner != .newOwner))
        );

    def blocker_changes($current; $previous):
      as_map($current) as $curr
      | as_map($previous) as $prev
      | (
          ($current | map(.identifier))
          | map(select($prev[.] != null))
          | map(
              {
                identifier: .,
                oldBlockers: ($prev[.].blockerIds // []),
                newBlockers: ($curr[.].blockerIds // [])
              }
            )
          | map(select(.oldBlockers != .newBlockers))
        );

    as_map($normalized) as $currentMap
    | as_map($previous) as $previousMap
    | (
        ($normalized | map(.identifier))
        - ($previous | map(.identifier))
      ) as $opened
    | (
        ($previous | map(.identifier))
        - ($normalized | map(.identifier))
      ) as $closed
    | status_owner_changes($normalized; $previous) as $statusOwnerDelta
    | blocker_changes($normalized; $previous) as $blockerDelta
    | ($normalized | map(select(.status == "blocked" or (.blockerIds | length) > 0))) as $blockedNow
    |

    "# paperclip-tracker-sync:v1\n" +
    "## Paperclip Active Issues Snapshot\n\n" +
    "- Synced at (UTC): `" + $stamp + "`\n" +
    "- Active statuses: `todo`, `in_progress`, `in_review`, `blocked`\n" +
    "- Issue count: `" + (($normalized | length) | tostring) + "`\n\n" +
    "### Active Issues\n\n" +
    (
      ($normalized | map(
        "- " + (.identifier // .id) +
        " | **" + (.status // "unknown") + "**" +
        " | owner: `" + (.assigneeName // "unassigned") + "`" +
        " | blockers: `" + blocker_summary(.) + "`" +
        " | " + (.title // "(untitled)")
      )) | join("\n")
    ) + "\n\n" +
    "### Changes Since Last Sync\n\n" +
    "- Status/owner changes:\n" +
    (
      if ($statusOwnerDelta | length) == 0 then
        "  - none\n"
      else
        ($statusOwnerDelta | map(
          "  - " + .identifier +
          ": status `" + .oldStatus + "` → `" + .newStatus + "`; owner `" + .oldOwner + "` → `" + .newOwner + "`"
        ) | join("\n")) + "\n"
      end
    ) +
    "- Newly opened active issues:\n" +
    (
      if ($opened | length) == 0 then
        "  - none\n"
      else
        ($opened | map("  - " + . + " | " + ($currentMap[.].title // "(untitled)")) | join("\n")) + "\n"
      end
    ) +
    "- Newly closed/left active set:\n" +
    (
      if ($closed | length) == 0 then
        "  - none\n"
      else
        ($closed | map("  - " + . + " | " + ($previousMap[.].title // "(untitled)")) | join("\n")) + "\n"
      end
    ) +
    "- Blocker changes:\n" +
    (
      if ($blockerDelta | length) == 0 then
        "  - none\n"
      else
        ($blockerDelta | map(
          "  - " + .identifier +
          ": blockers `" +
          (if (.oldBlockers | length) == 0 then "none" else (.oldBlockers | join(", ")) end) +
          "` → `" +
          (if (.newBlockers | length) == 0 then "none" else (.newBlockers | join(", ")) end) +
          "`"
        ) | join("\n")) + "\n"
      end
    ) + "\n" +
    "### Next Owner Action\n\n" +
    (
      if ($blockedNow | length) == 0 then
        "- No blocked active issues. Next owner action: advance in-progress items to review with verification evidence.\n"
      else
        "- `" + (($blockedNow | length) | tostring) + "` issue(s) are blocked. Next owner action: each blocked issue owner must post unblock owner/date and update blockers in Paperclip and GitHub.\n"
      end
    )
  '
)"

SYNC_FINGERPRINT="$(
  jq -cS -n \
    --argjson normalized "$NORMALIZED_JSON" '$normalized'
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

CONTENT_HASH="$(printf "%s" "$SYNC_FINGERPRINT" | hash_sha256)"
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
printf "%s" "$NORMALIZED_JSON" > "$STATE_DATA_PATH"
echo "saved sync hash: $STATE_PATH"
