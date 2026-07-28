# TestFlight Upload Runbook

How to archive and upload a WiredPart iOS beta build to TestFlight, and how the
2026-07-27 upload failure happened so it is never repeated.

## The one rule that matters

**Archive with an iOS device destination — never "My Mac (Mac Catalyst)".**

The project has `SUPPORTS_MACCATALYST = YES` (Catalyst is used for local Mac
compatibility only), so Xcode's destination menu offers a Mac destination.
Archiving with it produces a **macOS** bundle, and Xcode Organizer then runs
*Mac App Store* validation, which fails with:

- **90242** — `LSApplicationCategoryType` missing (Mac-only requirement)
- **90236** — missing 512pt@2x ICNS icon (Mac icon format)
- **90794** — `CFBundleIconName` missing

Per `docs/KEY-PRINCIPLES.md`, Catalyst is **not distributed**. TestFlight builds
are iOS-only.

## Preconditions (enforced by `scripts/check-app-store-readiness.sh`)

1. `AppIcon.appiconset` contains a real 1024×1024 PNG (no alpha channel — ASC
   rejects transparency in the marketing icon) with a `"filename"` entry in its
   `Contents.json`.
2. `INFOPLIST_KEY_LSApplicationCategoryType` set in the app target.
3. `CURRENT_PROJECT_VERSION` (build number) is **higher than any build already
   uploaded** to App Store Connect for this version. ASC rejects re-used build
   numbers. Bump it in `project.pbxproj` (app target, Debug + Release) before
   every upload.

## Upload — Xcode Organizer path (simplest)

1. Open `Weird Parts.xcworkspace`, scheme **WiredPart-iOS**.
2. Destination: **Any iOS Device (arm64)** — not a simulator, not My Mac.
3. Product → Archive.
4. Organizer opens → select the archive → **Distribute App** → **TestFlight &
   App Store** (App Store Connect) → Upload.
5. Wait for ASC processing (~10-30 min), then in App Store Connect →
   TestFlight, answer the **export compliance** question if prompted (the app
   embeds SQLCipher) and add the build to a tester group.

## Upload — CLI path

```bash
xcodebuild archive \
  -workspace "Weird Parts.xcworkspace" \
  -scheme "WiredPart-iOS" \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/WiredPart-iOS.xcarchive \
  -allowProvisioningUpdates
```

Verify the archive really is iOS before uploading:

```bash
plutil -p "/tmp/WiredPart-iOS.xcarchive/Products/Applications/Weird Parts.app/Info.plist" \
  | grep -E 'CFBundleSupportedPlatforms|CFBundleIconName|CFBundleVersion'
# Expect: iPhoneOS, AppIcon, and the bumped build number.
# A Catalyst archive has the plist at Weird Parts.app/Contents/Info.plist instead — abort if so.
```

Then export-with-upload (uses Xcode's signed-in ASC account; team `VV3HP9M7C2`):

```bash
cat > /tmp/exportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>VV3HP9M7C2</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath /tmp/WiredPart-iOS.xcarchive \
  -exportOptionsPlist /tmp/exportOptions.plist \
  -exportPath /tmp/WiredPart-export \
  -allowProvisioningUpdates
```

If CLI upload fails on App Store Connect authentication, fall back to the
Organizer path: copy the archive into `~/Library/Developer/Xcode/Archives/` so
it appears in Organizer, then upload from there.

## History

- **2026-07-27 23:07** — upload of build 1 failed: archive was Mac Catalyst
  (wrong destination) *and* the app had no icon at all (empty
  `AppIcon.appiconset`). Fixed 2026-07-28: placeholder icon added,
  `LSApplicationCategoryType` set, build bumped to 2, readiness script now
  guards both.
