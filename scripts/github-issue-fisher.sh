#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/github-issue-fisher.sh [--repo owner/repo] [--plans-dir path] [--reports-dir path] [--limit n] [--dry-run]

Runs one GitHub issue-fisher pass:
  1. verifies the canonical plan directory exists and is non-empty;
  2. classifies open GitHub issues in priority order: blocked, todo, backlog;
  3. performs an evidence scan against repo plans, DevTODOs, and code markers;
  4. writes a dated report with 1-3 issue-moving actions.

Default mode writes a local report only. Use the report to make the actual
GitHub issue/comment/label change after human or routine approval.
EOF
}

REPO="${GITHUB_REPO:-xXKillerNoobYT/Weird-Part-Run-2}"
PLANS_DIR="docs/plans"
REPORTS_DIR="docs/github-issue-fisher"
LIMIT=3
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?error: --repo requires owner/repo}"
      shift 2
      ;;
    --plans-dir)
      PLANS_DIR="${2:?error: --plans-dir requires a path}"
      shift 2
      ;;
    --reports-dir)
      REPORTS_DIR="${2:?error: --reports-dir requires a path}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?error: --limit requires a number}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in gh jq rg; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command missing: $cmd" >&2
    exit 1
  fi
done

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "error: expected repo in owner/repo form, got '$REPO'" >&2
  exit 1
fi
if [[ ! "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --limit must be a positive integer, got '$LIMIT'" >&2
  exit 1
fi
if [[ "$LIMIT" -gt 3 ]]; then
  echo "error: --limit is capped at 3 to keep each fisher run small-batch" >&2
  exit 1
fi
if [[ ! -d "$PLANS_DIR" ]]; then
  echo "error: plan directory '$PLANS_DIR' does not exist; pass --plans-dir to the canonical plan source" >&2
  exit 1
fi
PLAN_COUNT="$(find "$PLANS_DIR" -maxdepth 1 -type f \( -name '*.md' -o -name '*.markdown' \) | wc -l | tr -d ' ')"
if [[ "$PLAN_COUNT" -eq 0 ]]; then
  echo "error: plan directory '$PLANS_DIR' has no markdown plans; refusing placeholder issue fishing" >&2
  exit 1
fi

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP_DIR="${STAMP//:/-}"
RUN_DIR="$REPORTS_DIR/$STAMP_DIR"
mkdir -p "$RUN_DIR"

ISSUES_JSON="$RUN_DIR/open-issues.json"
FINDINGS_JSON="$RUN_DIR/evidence-findings.json"
ACTIONS_JSON="$RUN_DIR/actions.json"
REPORT_MD="$RUN_DIR/report.md"
LATEST_MD="$REPORTS_DIR/latest-report.md"

gh issue list \
  --repo "$REPO" \
  --state open \
  --limit 200 \
  --json number,title,labels,updatedAt,url > "$ISSUES_JSON"

jq -n \
  --argjson issues "$(cat "$ISSUES_JSON")" \
  --argjson limit "$LIMIT" '
  def bucket($labelNames):
    if ($labelNames | index("blocked")) then "blocked"
    elif (($labelNames | any(test("^priority:P[0-3]$"))) or ($labelNames | index("triage")) or ($labelNames | index("bug")) or ($labelNames | index("enhancement"))) then "todo"
    else "backlog"
    end;
  $issues
  | map(. as $issue | ([$issue.labels[].name]) as $labelNames | $issue + {bucket: bucket($labelNames), labelNames: $labelNames})
  | group_by(.bucket)
  | map({
      bucket: .[0].bucket,
      items: (
        sort_by(
          if (.labelNames | index("priority:P0")) then 0
          elif (.labelNames | index("priority:P1")) then 1
          elif (.labelNames | index("priority:P2")) then 2
          elif (.labelNames | index("priority:P3")) then 3
          else 4 end,
          .updatedAt
        )
      )
    })
  | . as $groups
  | reduce ["blocked","todo","backlog"][] as $bucket ([]; . + ([$groups[] | select(.bucket == $bucket) | .items[]]))
  | .[:$limit]
  | map({
      type: "move-existing-github-issue",
      bucket,
      issue: ("#" + (.number | tostring)),
      title,
      url,
      evidence: ("Open GitHub issue classified as " + .bucket + " from labels: " + ((.labelNames | join(", ")) // "none")),
      nextAction: (
        if .bucket == "blocked" then "Resolve or replace the blocker before starting new implementation."
        elif .bucket == "todo" then "Assign the smallest implementation owner or move into an active Paperclip child issue."
        else "Promote only if plan scan confirms this is still relevant."
        end
      )
    })' > "$ACTIONS_JSON"

TMP_FINDINGS="$(mktemp)"
trap 'rm -f "$TMP_FINDINGS"' EXIT

{
  rg -n --glob '*.md' 'GitHub issue PENDING|needs GitHub issue|PENDING GitHub|TODO|FIXME|HACK' docs/DevTODO "$PLANS_DIR" 2>/dev/null || true
  rg -n --glob '*.swift' 'TODO|FIXME|HACK|try\?' core/Sources "Weird Parts IOS/Weird Parts IOS" 2>/dev/null || true
} | head -n 80 > "$TMP_FINDINGS"

jq -Rn '
  [inputs | select(length > 0) | capture("(?<path>[^:]+):(?<line>[0-9]+):(?<text>.*)")?]
  | map(select(. != null))
  | map({
      type: "repo-evidence",
      path,
      line: (.line | tonumber),
      excerpt: (.text | gsub("^\\s+"; "") | .[:220])
    })' < "$TMP_FINDINGS" > "$FINDINGS_JSON"

ACTION_COUNT="$(jq 'length' "$ACTIONS_JSON")"
FINDING_COUNT="$(jq 'length' "$FINDINGS_JSON")"

{
  echo "# GitHub Issue Fisher Report"
  echo
  printf -- "- Repository: \`%s\`\n" "$REPO"
  printf -- "- Run timestamp (UTC): \`%s\`\n" "$STAMP"
  printf -- "- Mode: \`%s\`\n" "$([[ "$DRY_RUN" -eq 1 ]] && echo dry-run || echo report-only)"
  printf -- "- Plan source: \`%s\` (%s markdown files)\n" "$PLANS_DIR" "$PLAN_COUNT"
  printf -- "- Priority order: \`blocked -> todo -> backlog\`\n"
  printf -- "- Selected actions: \`%s\`\n" "$ACTION_COUNT"
  printf -- "- Evidence findings sampled: \`%s\`\n" "$FINDING_COUNT"
  echo
  echo "## Selected Issue-Moving Actions"
  echo
  jq -r '
    if length == 0 then
      "_No open GitHub issues were available for movement._"
    else
      .[] |
      "### " + .issue + " — " + .title + "\n" +
      "- Bucket: `" + .bucket + "`\n" +
      "- URL: " + .url + "\n" +
      "- Evidence: " + .evidence + "\n" +
      "- Next action: " + .nextAction + "\n"
    end' "$ACTIONS_JSON"
  echo
  echo "## Evidence Scan Sample"
  echo
  jq -r '
    if length == 0 then
      "_No repo evidence markers found in the scanned scope._"
    else
      .[:20][] | "- `" + .path + ":" + (.line | tostring) + "` — " + .excerpt
    end' "$FINDINGS_JSON"
  echo
  echo "## Guardrails"
  echo
  echo "- This run refuses to proceed when the plan directory is missing or empty."
  echo "- The workflow selects at most 3 actions per run."
  echo "- Reports are evidence; GitHub mutation still requires an explicit follow-up owner or approved routine path."
} > "$REPORT_MD"

cp "$REPORT_MD" "$LATEST_MD"

echo "wrote: $REPORT_MD"
echo "wrote: $LATEST_MD"
echo "wrote: $ACTIONS_JSON"
echo "wrote: $FINDINGS_JSON"
