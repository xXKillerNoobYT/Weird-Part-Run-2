#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <bundle-markdown-path>" >&2
  exit 2
fi

bundle_path="$1"

if [[ ! -f "$bundle_path" ]]; then
  echo "FAIL: bundle file not found: $bundle_path" >&2
  exit 2
fi

errors=()

require_pattern() {
  local pattern="$1"
  local message="$2"
  if ! rg -q "$pattern" "$bundle_path"; then
    errors+=("$message")
  fi
}

# 1) Artifact links
if ! rg -qi '^\s*Artifact Links\s*:' "$bundle_path"; then
  errors+=("missing required field: Artifact Links")
elif ! rg -qi '^\s*-\s+\[[^]]+\]\([^)]*\)' "$bundle_path"; then
  errors+=("artifact links must include at least one markdown link bullet")
fi

# 2) Acceptance checklist
if ! rg -qi '^\s*Acceptance Checklist\s*:' "$bundle_path"; then
  errors+=("missing required field: Acceptance Checklist")
else
  if ! rg -q '^\s*-\s+\[[xX]\]\s+' "$bundle_path"; then
    errors+=("acceptance checklist must include at least one completed checkbox")
  fi
  if rg -q '^\s*-\s+\[\s\]\s+' "$bundle_path"; then
    errors+=("acceptance checklist contains unchecked items")
  fi
fi

# 3) Unresolved risk declaration
if ! rg -qi '^\s*Unresolved Risks\s*:' "$bundle_path"; then
  errors+=("missing required field: Unresolved Risks")
else
  require_pattern '^\s*Unresolved Risks\s*:\s*\S.+' "unresolved risks declaration cannot be blank"
fi

# 4) Reproduction command/path
if ! rg -qi '^\s*Reproduction\s*:' "$bundle_path"; then
  errors+=("missing required field: Reproduction")
fi
require_pattern '^\s*Command\s*:\s*`[^`]+`' "reproduction command must be present and wrapped in backticks"
require_pattern '^\s*Path\s*:\s*`[^`]+`' "reproduction path must be present and wrapped in backticks"

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "FAIL: closure bundle is incomplete"
  for err in "${errors[@]}"; do
    echo "- $err"
  done
  echo "fail-open/fail-closed: FAIL-CLOSED for parent closure gate; escalate to CTO when intentional override is needed"
  exit 1
fi

echo "PASS: closure bundle completeness validated"
echo "fail-open/fail-closed: FAIL-CLOSED for parent closure gate; owner escalation: CTO"
