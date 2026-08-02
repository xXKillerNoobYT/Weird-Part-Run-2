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

## What-to-Test notes — known-issues process (owner 2026-08-01)

Every build's notes include the OPEN and AWAITING-CONFIRMATION sections of
`docs/app-store/testflight-notes/KNOWN-ISSUES.md` — reported bugs stay listed
with a fix-confidence rating until the reporting tester confirms the fix, then
move to the confirmed log (never deleted). Behavior changes are announced in
the notes the build they ship. Feedback is swept daily; tester follow-up
questions may be sent from weirdnow@icloud.com (owner-authorized, report each
send). Kevin's and external testers' reports are never interpreted by guess —
ask the owner.

## Release channels (owner directive 2026-07-31)

> `App verison/` is the EXTERNAL trigger only (owner 2026-08-01): routine PR
> merges never touch it — internal builds fire from any `main` edit on their
> own. Only an intentional external release changes that folder.

Two TestFlight channels with very different costs and cadences:

| | **Internal** ("Home Base" group) | **External** ("Camp 1" group, public link) |
|---|---|---|
| Who | Owner's own devices (weirdnow@icloud.com) | Public beta testers via the ASC public link |
| Apple review | None — build just has to pass | Apple **beta app review** + heavy Xcode Cloud processing |
| Trigger | Any `main` edit (automatic), or a local archive+upload; never change `App verison/` for an internal build | Intentional change to the external channel file in `App verison/`, then the Xcode Cloud workflow with the full action set (Build/Test iOS+macOS, Archive, Analyze, Notarize, TestFlight External Testing post-action) |
| Test bar | PR gates green | **FULL suite green on every device in the recommended testing package** (owner 2026-08-01) — any red/skip on any device blocks the push |
| Cadence | Every main edit (automatic) | **At most one per 5 days, at least one per 14** (owner 2026-08-01) — a stable-ish external release every 5–14 days; owner-gated |

The `App verison/` folder (spelling is load-bearing — Xcode Cloud's external
release condition references the URL-encoded name) holds one machine-parseable
version file per channel: `INTERNAL-BETA.md`, `PUBLIC-BETA.md`,
`PUBLIC-RELEASE.md`. It is external-only: do not bump `INTERNAL-BETA.md` for
an internal build. An intentional external channel bump must ride the SAME
commit/PR as everything its build needs (build number, notes) — never bump a
channel file "in advance."

App Store Connect status emails land in Apple Mail for weirdnow@icloud.com on
the shared Mac — check there (AppleScript/`osascript` against Mail.app) for
processing results, review verdicts, and compliance prompts. Beta feedback is
checked at least daily via the local ASC feedback script (below).

## Release notes — REQUIRED for every beta build (owner directive 2026-07-31)

Every TestFlight build ships with **"What's changed"** and **"What to look for"**
notes. A build without them is not done uploading.

1. **Write the notes BEFORE uploading** to
   `docs/app-store/testflight-notes/build-<N>.md` (template in that directory).
   Source the "What's changed" list from the PRs merged since the previous
   build's commit (`git log <prev-build-tag-or-sha>..HEAD --oneline` filtered to
   user-visible changes — testers don't care about CI plumbing). "What to look
   for" names the specific screens/flows to exercise, ALWAYS including re-tests
   of every open piece of beta feedback (check with the local feedback script,
   see below).
2. **Set them on the build in App Store Connect** once processing finishes:
   TestFlight → the build → Test Details ("What to Test"), or via the ASC API
   `betaBuildLocalizations` (`whatsNew` field). The internal Home Base group
   sees these notes in the TestFlight app.
3. **Check beta feedback first**: `~/.claude/scripts/ascenv/bin/python
   ~/.claude/scripts/asc_feedback.py` lists screenshot + crash feedback
   (local-only script; the ASC key never enters this public repo). Every
   feedback item gets a GitHub issue and a line in the next build's "What to
   look for".

## History

- **2026-07-27 23:07** — upload of build 1 failed: archive was Mac Catalyst
  (wrong destination) *and* the app had no icon at all (empty
  `AppIcon.appiconset`). Fixed 2026-07-28: placeholder icon added,
  `LSApplicationCategoryType` set, build bumped to 2, readiness script now
  guards both.
