#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift is required but was not found in PATH" >&2
  exit 1
fi

cd "$CORE_DIR"

echo "==> WiredPartCore smoke: swift build"
swift build

echo "==> WiredPartCore smoke: tests with coverage"
swift test --enable-code-coverage

echo "==> WiredPartCore smoke: source-only coverage gate"
"$ROOT_DIR/scripts/wiredpartcore-source-coverage.py"

echo "==> WiredPartCore smoke gate passed"
