#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/paperclip-dedupe-gh-synced-issues.sh [--apply] [--status status-list]

Options:
  --apply                 Perform API updates (default is report-only dry run)
  --status <csv>          Statuses to scan (default: todo,in_progress,in_review,blocked,backlog)

Environment:
  PAPERCLIP_API_URL       Required
  PAPERCLIP_API_KEY       Required
  PAPERCLIP_COMPANY_ID    Required
  PAPERCLIP_RUN_ID        Required when using --apply (audit trail)

Behavior:
  - Groups active Paperclip issues by GitHub issue number parsed from title prefix [GH#<n>]
  - Keeps one canonical issue per group (highest-ranked status, then oldest createdAt)
  - Marks non-canonical duplicates as cancelled with a comment pointing to canonical issue
USAGE
}

APPLY=0
STATUSES="todo,in_progress,in_review,blocked,backlog"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --status)
      STATUSES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

: "${PAPERCLIP_API_URL:?error: PAPERCLIP_API_URL is required}"
: "${PAPERCLIP_API_KEY:?error: PAPERCLIP_API_KEY is required}"
: "${PAPERCLIP_COMPANY_ID:?error: PAPERCLIP_COMPANY_ID is required}"

if [[ "$APPLY" -eq 1 ]]; then
  : "${PAPERCLIP_RUN_ID:?error: PAPERCLIP_RUN_ID is required for --apply}"
fi

ISSUES_JSON="$(curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues?status=$STATUSES")"

REPORT_JSON="$(jq -c '
  def gh_num: ((try (.title | capture("^\\[GH#(?<n>[0-9]+)\\]").n) catch null));
  def status_rank:
    if .status == "in_progress" then 0
    elif .status == "in_review" then 1
    elif .status == "todo" then 2
    elif .status == "blocked" then 3
    elif .status == "backlog" then 4
    else 99 end;

  . as $rows
  | [ $rows[]
      | . + { ghNumber: gh_num }
      | select(.ghNumber != null)
      | {
          id, identifier, title, status, priority, createdAt, updatedAt, ghNumber,
          rank: status_rank
        }
    ] as $ghRows
  | ($ghRows | group_by(.ghNumber)) as $groups
  | {
      totalRows: ($ghRows | length),
      uniqueGithubNumbers: ($ghRows | map(.ghNumber) | unique | length),
      duplicateRows: (($ghRows | length) - ($ghRows | map(.ghNumber) | unique | length)),
      groups: [
        $groups[]
        | sort_by(.rank, .createdAt, .identifier)
        | {
            ghNumber: .[0].ghNumber,
            canonical: .[0],
            duplicates: (.[1:] // [])
          }
      ]
    }
' <<<"$ISSUES_JSON")"

printf '%s\n' "$REPORT_JSON" | jq '{totalRows, uniqueGithubNumbers, duplicateRows}'

if [[ "$APPLY" -ne 1 ]]; then
  echo "dry-run: no issue updates performed"
  exit 0
fi

printf '%s\n' "$REPORT_JSON" | jq -c '.groups[] | select((.duplicates | length) > 0)' | while IFS= read -r group; do
  canonical_id="$(jq -r '.canonical.id' <<<"$group")"
  canonical_identifier="$(jq -r '.canonical.identifier' <<<"$group")"
  gh_number="$(jq -r '.ghNumber' <<<"$group")"

  jq -c '.duplicates[]' <<<"$group" | while IFS= read -r dup; do
    dup_id="$(jq -r '.id' <<<"$dup")"
    dup_identifier="$(jq -r '.identifier' <<<"$dup")"

    comment="Cancelled duplicate [GH#${gh_number}] issue. Canonical issue is [${canonical_identifier}](/WEI/issues/${canonical_identifier})."

    payload="$(jq -n --arg status "cancelled" --arg comment "$comment" '{status: $status, comment: $comment}')"

    curl -fsS \
      -X PATCH \
      -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
      -H "Content-Type: application/json" \
      -H "X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID" \
      -d "$payload" \
      "$PAPERCLIP_API_URL/api/issues/$dup_id" >/dev/null

    echo "cancelled duplicate: $dup_identifier -> $canonical_identifier"
  done
done

POST_JSON="$(curl -fsS \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues?status=$STATUSES")"

printf '%s\n' "$POST_JSON" | jq -r '
  [ .[] | select(.title|test("^\\[GH#[0-9]+\\]")) | .title | capture("^\\[GH#(?<n>[0-9]+)\\]") | .n ]
  | { totalRows: length, uniqueGithubNumbers: (unique|length), duplicateRows: (length - (unique|length)) }
'
