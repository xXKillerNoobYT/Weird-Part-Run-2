#!/usr/bin/env bash
set -euo pipefail

EVENT_PATH="${GITHUB_EVENT_PATH:-}"
if [[ "${1:-}" == "--event-file" ]]; then
  EVENT_PATH="${2:-}"
fi

if [[ -z "$EVENT_PATH" || ! -f "$EVENT_PATH" ]]; then
  echo "critical-review-gate: missing pull_request event JSON (set GITHUB_EVENT_PATH or pass --event-file <path>)" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "critical-review-gate: jq is required" >&2
  exit 2
fi

pr_body="$(jq -r '.pull_request.body // ""' "$EVENT_PATH")"
pr_number="$(jq -r '.pull_request.number // ""' "$EVENT_PATH")"
labels_csv="$(jq -r '[.pull_request.labels[]?.name] | join(",")' "$EVENT_PATH")"

lc_body="$(printf '%s' "$pr_body" | tr '[:upper:]' '[:lower:]')"
is_critical=false

if printf '%s' "$labels_csv" | tr '[:upper:]' '[:lower:]' | grep -q 'critical-review'; then
  is_critical=true
fi

if printf '%s' "$lc_body" | grep -q -- '- \[x\] critical-review lane'; then
  is_critical=true
fi

if [[ "$is_critical" != true ]]; then
  echo "critical-review-gate: PR #${pr_number:-unknown} is fast-review lane; gate bypassed."
  exit 0
fi

missing=()

if ! printf '%s' "$lc_body" | grep -q -- '- \[x\] claudereviewer sign-off captured'; then
  missing+=("ClaudeReviewer sign-off checkbox")
fi

if ! printf '%s' "$lc_body" | grep -q -- '- \[x\] gptreviewer sign-off captured'; then
  missing+=("GPTReviewer sign-off checkbox")
fi

requested_at="$(printf '%s' "$pr_body" | sed -n 's/^[[:space:]-]*Critical review requested at (UTC):[[:space:]]*//p' | head -n1)"
approved_at="$(printf '%s' "$pr_body" | sed -n 's/^[[:space:]-]*Critical review approved at (UTC):[[:space:]]*//p' | head -n1)"

if [[ -z "${requested_at// }" ]]; then
  missing+=("Critical review requested at (UTC) timestamp")
fi

if [[ -z "${approved_at// }" ]]; then
  missing+=("Critical review approved at (UTC) timestamp")
fi

if (( ${#missing[@]} > 0 )); then
  echo "critical-review-gate: PR #${pr_number:-unknown} is marked critical-review but metadata is incomplete:" >&2
  for item in "${missing[@]}"; do
    echo "- missing: $item" >&2
  done
  exit 1
fi

echo "critical-review-gate: PR #${pr_number:-unknown} critical-review metadata complete."
