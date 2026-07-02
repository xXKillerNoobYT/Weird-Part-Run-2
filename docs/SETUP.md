# WiredPart Local Setup

Tracking:

- GitHub: [xXKillerNoobYT/Weird-Part-Run-2#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942)
- Paperclip parent: `WEI-3096`
- Paperclip active implementation: `WEI-3099`
- Paperclip QA review: `WEI-3100`

This guide is for the current native iOS and Swift package repository. Older web/server deployment notes may still exist in historical plans, but they are not the front-door setup path for this repo.

## Prerequisites

| Requirement | Purpose |
| --- | --- |
| macOS with Xcode 26.2+ installed | builds the SwiftUI iOS app and runs simulators (repo verified with Xcode 26.5) |
| Xcode command line tools | provides `xcodebuild`, `xcrun`, SwiftPM |
| Swift 6-compatible toolchain | builds `core/Package.swift` (swift-tools-version 6.0) |
| GitHub CLI `gh` | optional, for PR/runner checks |
| Python 3 | optional, for repo guard scripts |

## Platform Requirements

<!-- Verify: grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' "Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj" | sort -u -->

| Target | Minimum version |
| --- | --- |
| iOS app (iPhone/iPad, device or simulator) | iOS 26.2 (`IPHONEOS_DEPLOYMENT_TARGET = 26.2`) |
| macOS scheme (`WiredPart-macOS`, experimental) | macOS 26.4 |
| Core package (`core/Package.swift`) | iOS 17 / macOS 14 — `swift test` runs on Macs that cannot run the app target |
| Xcode | 26.2 or newer (needs the iOS 26.2 SDK) |

A beta tester's iPhone or iPad must be on iOS 26.2 or later to run the app.

Check local tools:

```bash
xcodebuild -version
swift --version
python3 --version
gh --version
```

## Clone And Open

```bash
git clone git@github.com:xXKillerNoobYT/Weird-Part-Run-2.git
cd Weird-Part-Run-2
open "Weird Parts IOS/Weird Parts.xcodeproj"
```

Tip: the repo's git history is large (GitHub #1339). For a much faster first clone, use a partial clone — it fetches file contents on demand:

```bash
# SSH (needs configured SSH keys)
git clone --filter=blob:none git@github.com:xXKillerNoobYT/Weird-Part-Run-2.git
# HTTPS (no key setup — copy/paste friendly)
git clone --filter=blob:none https://github.com/xXKillerNoobYT/Weird-Part-Run-2.git
```

The app target lives under `Weird Parts IOS/`. The shared package lives under `core/` and is the preferred place for business logic, persistence, sync, QR/OCR, and service tests.

## Build Entry Points And Schemes

The repo has two Xcode entry points. Both resolve the same packages; they differ in schemes.

<!-- Verify: xcodebuild -list -project "Weird Parts IOS/Weird Parts.xcodeproj" ; xcodebuild -list -workspace "Weird Parts.xcworkspace" -->

| Entry point | Schemes | Use for |
| --- | --- | --- |
| `Weird Parts IOS/Weird Parts.xcodeproj` | `Weird Parts`, `WiredPartCore` | quick app-only build/test work (the commands below) |
| `Weird Parts.xcworkspace` (repo root) | `WiredPart-iOS`, `WiredPart-iOS-Stage9-Smokes`, `WiredPart-macOS`, `WiredPartCore` | the beta smoke gate ([docs/testing/wei-3091-stage-9-beta-smoke-package.md](testing/wei-3091-stage-9-beta-smoke-package.md)) and the experimental macOS scheme |

The workspace filename contains a space — quote `Weird Parts.xcworkspace` exactly in commands.

## Build The Core Package

```bash
cd core
swift build
swift test
```

Use focused tests while iterating:

```bash
cd core
swift test --filter "AuthServiceTests"
```

## Build The iOS App

From the repo root:

```bash
xcrun simctl list devices available

xcodebuild \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts" \
  -destination 'generic/platform=iOS Simulator' \
  build
```

For manual simulator validation, replace the generic destination with an installed device from `xcrun simctl list devices available` and record the destination in your handoff.

## Run App Tests

```bash
xcodebuild \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts" \
  -destination 'generic/platform=iOS Simulator' \
  test
```

For UI work, capture route/screen evidence using Xcode test attachments, simulator screenshots, or a concise manual note with device, orientation, and result. See [QA-PROCESS.md](QA-PROCESS.md).

## Repo Guards

Before handing off:

```bash
git diff --check
python3 scripts/guard-tracked-artifacts.py
git status --short
```

Do not commit:

- `.env`, tokens, credentials, provisioning secrets, or API keys.
- Local databases, DerivedData, build products, caches, or logs.
- Runtime screenshots unless the issue explicitly requests checked-in documentation images.
- Temporary agent workspaces or generated artifacts.

## GitHub Actions And PR Validation

Static checks can run on GitHub-hosted Linux/macOS as configured. For iOS/macOS/Xcode PR work, use the local self-hosted Mac runner path before declaring CI blocked by hosted runner billing/capacity.

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'

gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10
grep -R "runs-on:" .github/workflows
```

Known local runner:

- Directory: `/Users/IA/actions-runner/Weird-Part-Run-2`
- Service: `IA-Mac-WPR2`
- Labels: `self-hosted`, `macOS`, `ARM64`/`arm64`, `xcode`, `ios`, `local-mac`

Runner tracking: GitHub [#943](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/943), Paperclip `WEI-3097`.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Swift package dependency fails | Confirm `core/Package.resolved` is present and rerun `swift package resolve` from `core`. |
| Simulator destination not found | Run `xcrun simctl list devices available` and use an installed device name. |
| App build cannot find package products | Reopen the Xcode project and let package resolution finish. |
| Xcode test hangs in CI | Check local runner availability and workflow `runs-on` labels before treating it as a cloud blocker. |
| Guard script fails | Remove generated/runtime artifact from tracking or update ignore/guard rules only when the artifact is intentionally source-controlled. |

## Next Reads

- [README.md](../README.md) for the repo map.
- [WORKING-AREAS.md](WORKING-AREAS.md) for area ownership.
- [QA-PROCESS.md](QA-PROCESS.md) for evidence expectations.
