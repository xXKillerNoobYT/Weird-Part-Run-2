#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_paths=(
  "$ROOT_DIR/docs/app-store/screenshots"
  "$ROOT_DIR/docs/app-store/description.md"
  "$ROOT_DIR/docs/app-store/privacy-labels.md"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required App Store metadata path: ${path#$ROOT_DIR/}" >&2
    exit 1
  fi
done

pbxproj="$ROOT_DIR/Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj"
if grep -q 'MARKETING_VERSION = 1\.0\.0\.0;' "$pbxproj"; then
  echo "Invalid MARKETING_VERSION found in main iOS app target: 1.0.0.0" >&2
  exit 1
fi

echo "app-store readiness check passed"
