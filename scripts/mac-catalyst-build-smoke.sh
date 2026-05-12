#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-"$ROOT_DIR/docs/testing/artifacts/mac-catalyst-smoke"}"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
LOG_PATH="$ARTIFACT_DIR/mac-catalyst-build-smoke-$STAMP.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required but was not found in PATH" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"

echo "==> Mac Catalyst build smoke: WiredPart-iOS"
echo "==> Writing log: $LOG_PATH"

cd "$ROOT_DIR"

xcodebuild build \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS" \
  -destination "platform=macOS,variant=Mac Catalyst" \
  | tee "$LOG_PATH"

echo "==> Mac Catalyst build smoke passed"
