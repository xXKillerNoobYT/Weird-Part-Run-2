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

# App Store Connect rejects any upload whose primary app icon slot is empty
# (ASC 90236/90794, hit on the 2026-07-27 upload): the icon set must name a
# file and that file must exist, or actool emits no Assets.car and no
# CFBundleIconName.
appiconset="$ROOT_DIR/Weird Parts IOS/Weird Parts IOS/Assets.xcassets/AppIcon.appiconset"
icon_filename="$(sed -n 's/.*"filename" *: *"\([^"]*\)".*/\1/p' "$appiconset/Contents.json" 2>/dev/null | head -n 1)"
if [[ -z "$icon_filename" ]]; then
  echo "AppIcon.appiconset has no image filename — App Store uploads fail without an app icon (ASC 90236/90794)" >&2
  exit 1
fi
if [[ ! -f "$appiconset/$icon_filename" ]]; then
  echo "AppIcon.appiconset references missing image file: $icon_filename" >&2
  exit 1
fi

# LSApplicationCategoryType is required for Mac Catalyst uploads (ASC 90242)
# and expected App Store metadata for iOS.
if ! grep -q 'INFOPLIST_KEY_LSApplicationCategoryType' "$pbxproj"; then
  echo "Missing INFOPLIST_KEY_LSApplicationCategoryType in iOS app target (ASC 90242)" >&2
  exit 1
fi

echo "app-store readiness check passed"
