#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --repo owner/name [--output-dir docs/github-issue-sync] [--state all|open|closed]

Creates a timestamped GitHub issues snapshot and updates latest summary files.
USAGE
}

repo=""
output_dir="docs/github-issue-sync"
state="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --state)
      state="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$repo" ]]; then
  echo "--repo is required" >&2
  usage >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

ts_utc="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"
run_dir="${output_dir}/${ts_utc}"
mkdir -p "$run_dir"

json_path="${run_dir}/issues.json"
markdown_path="${run_dir}/summary.md"

# Pull full issue list with pagination.
gh issue list \
  --repo "$repo" \
  --state "$state" \
  --limit 1000 \
  --json number,title,state,labels,assignees,url,createdAt,updatedAt,closedAt,author > "$json_path"

open_count="$(jq '[.[] | select(.state == "OPEN")] | length' "$json_path")"
closed_count="$(jq '[.[] | select(.state == "CLOSED")] | length' "$json_path")"
total_count="$(jq 'length' "$json_path")"

cat > "$markdown_path" <<MD
# GitHub Issue Sync Snapshot

- Repository: ${repo}
- Run timestamp (UTC): ${ts_utc}
- Requested state filter: ${state}
- Total issues captured: ${total_count}
- Open issues: ${open_count}
- Closed issues: ${closed_count}

## Most Recently Updated (Top 20)

| # | Title | State | Updated (UTC) |
|---|---|---|---|
MD

jq -r '
  sort_by(.updatedAt) | reverse | .[:20] |
  .[] | "| [#\(.number)](\(.url)) | \(.title | gsub("\\|"; "\\\\|")) | \(.state) | \(.updatedAt) |"
' "$json_path" >> "$markdown_path"

cp "$json_path" "${output_dir}/latest.json"
cp "$markdown_path" "${output_dir}/latest.md"

cat > "${run_dir}/run-metadata.json" <<MD
{
  "repo": "${repo}",
  "state": "${state}",
  "timestampUtc": "${ts_utc}",
  "total": ${total_count},
  "open": ${open_count},
  "closed": ${closed_count},
  "artifacts": {
    "issuesJson": "${json_path}",
    "summaryMarkdown": "${markdown_path}"
  }
}
MD

echo "Sync complete"
echo "Run directory: ${run_dir}"
echo "Summary: ${markdown_path}"
echo "Raw JSON: ${json_path}"
