#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-"$ROOT_DIR/docs/testing/artifacts/mac-catalyst-launch-smoke"}"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
LOG_PATH="$ARTIFACT_DIR/mac-catalyst-launch-smoke-$STAMP.log"
SCREENSHOT_PATH="$ARTIFACT_DIR/mac-catalyst-launch-smoke-$STAMP.png"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/tmp}/mac-catalyst-launch-smoke.XXXXXX")"

cleanup() {
  killall "Weird Parts" >/dev/null 2>&1 || true
  rm -rf "$DERIVED_DATA_PATH"
}
trap cleanup EXIT

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required but was not found in PATH" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"

echo "==> Mac Catalyst launch smoke: WiredPart-iOS" | tee "$LOG_PATH"
echo "==> Writing log: $LOG_PATH" | tee -a "$LOG_PATH"

cd "$ROOT_DIR"

xcodebuild build \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS,variant=Mac Catalyst" \
  | tee -a "$LOG_PATH"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-maccatalyst/Weird Parts.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: failed to locate built Weird Parts.app under DerivedData" | tee -a "$LOG_PATH" >&2
  exit 1
fi

echo "==> Launching: $APP_PATH" | tee -a "$LOG_PATH"
killall "Weird Parts" >/dev/null 2>&1 || true
open -n "$APP_PATH" --args -UITesting -UITestPrimaryModule parts >> "$LOG_PATH" 2>&1

sleep 10

if ! pgrep -x "Weird Parts" >/dev/null; then
  echo "error: Weird Parts process was not running after direct Catalyst launch" | tee -a "$LOG_PATH" >&2
  exit 1
fi

echo "==> Weird Parts process is running with UI-test routing arguments" | tee -a "$LOG_PATH"
pgrep -fl "Weird Parts" | tee -a "$LOG_PATH"

if command -v screencapture >/dev/null 2>&1; then
  if screencapture -x "$SCREENSHOT_PATH" >> "$LOG_PATH" 2>&1; then
    echo "==> Screenshot: $SCREENSHOT_PATH" | tee -a "$LOG_PATH"
  else
    echo "warning: screencapture failed; check Screen Recording permission for this shell/Xcode host" | tee -a "$LOG_PATH"
  fi
fi

echo "==> Mac Catalyst launch smoke passed" | tee -a "$LOG_PATH"
