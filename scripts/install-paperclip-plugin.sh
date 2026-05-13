#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="wiredpart-paperclip"
PLUGIN_SOURCE_DIR="$REPO_ROOT/plugins/$PLUGIN_NAME"

if [[ ! -f "$PLUGIN_SOURCE_DIR/.codex-plugin/plugin.json" ]]; then
  echo "Missing plugin manifest at $PLUGIN_SOURCE_DIR/.codex-plugin/plugin.json" >&2
  exit 1
fi

TARGET_ROOT="${CODEX_HOME:-$HOME/.codex}"
TARGET_PLUGINS_DIR="$TARGET_ROOT/plugins"
TARGET_PLUGIN_DIR="$TARGET_PLUGINS_DIR/$PLUGIN_NAME"
MARKETPLACE_FILE="$TARGET_ROOT/.agents/plugins/marketplace.json"

mkdir -p "$TARGET_PLUGINS_DIR" "$(dirname "$MARKETPLACE_FILE")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: required command missing: python3" >&2
  exit 1
fi

if [[ -L "$TARGET_PLUGIN_DIR" || -e "$TARGET_PLUGIN_DIR" ]]; then
  rm -rf "$TARGET_PLUGIN_DIR"
fi
ln -s "$PLUGIN_SOURCE_DIR" "$TARGET_PLUGIN_DIR"

python3 - "$MARKETPLACE_FILE" "$PLUGIN_NAME" <<'PY'
import json
import pathlib
import sys

marketplace_path = pathlib.Path(sys.argv[1])
plugin_name = sys.argv[2]
plugin_entry = {
    "name": plugin_name,
    "source": {
        "source": "local",
        "path": f"./plugins/{plugin_name}"
    },
    "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
    },
    "category": "Productivity"
}

if marketplace_path.exists():
    with marketplace_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {
        "name": "local-marketplace",
        "interface": {
            "displayName": "Local Marketplace"
        },
        "plugins": []
    }

if "plugins" not in data or not isinstance(data["plugins"], list):
    data["plugins"] = []

updated = False
for i, existing in enumerate(data["plugins"]):
    if isinstance(existing, dict) and existing.get("name") == plugin_name:
        data["plugins"][i] = plugin_entry
        updated = True
        break

if not updated:
    data["plugins"].append(plugin_entry)

with marketplace_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "Installed plugin '$PLUGIN_NAME'"
echo "Linked: $TARGET_PLUGIN_DIR -> $PLUGIN_SOURCE_DIR"
echo "Marketplace: $MARKETPLACE_FILE"
