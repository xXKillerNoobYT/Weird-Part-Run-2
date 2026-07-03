# WiredPart — Dependency Reference

> Last updated: 2026-07-01 (GitHub #1334)
> Purpose: Dependency map for the current native iOS / Swift package repository.
>
> The 2026-03-10 edition of this file documented the retired Tauri/React/FastAPI stack (pip + npm dependencies). Those directories (`backend/`, `frontend/`, `src/`, `src-tauri/`) no longer exist in the working tree; the old lists are preserved in git history.

---

## Swift Package Dependencies

Declared in [`core/Package.swift`](../core/Package.swift) and pinned by the committed [`core/Package.resolved`](../core/Package.resolved).

<!-- Verify: cat core/Package.swift && cat core/Package.resolved -->

| Package | Version | Why |
|---------|---------|-----|
| [duckduckgo/GRDB.swift](https://github.com/duckduckgo/GRDB.swift) | `exact: 2.4.2-1` (rev `80cae244`) | Database layer. DuckDuckGo's fork bundles GRDB 7.x + SQLCipher 4.7.0 as a prebuilt XCFramework, encrypting the whole SQLite database at rest. Chosen over plain `groue/GRDB.swift` because it keeps the same `GRDB` product name — zero import-site changes across 300+ Swift files. |
| [weichsel/ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | `from: 0.9.19` (resolved: 0.9.20) | ZIP archive support (backups, XLSX import/export). |

**Do not bump GRDB casually.** The fork is pinned exactly to `2.4.2-1` because newer fork tags (e.g. v3.7.0) fail macOS CLI `swift test` with `cannot find 'strcmp' in scope` under Swift 6 strict-module mode. `Package.resolved` is committed so every environment resolves the same revision. See the comment block in `core/Package.swift` before changing anything.

Everything else is Apple system frameworks (SwiftUI, GRDB's bundled SQLite/SQLCipher, MultipeerConnectivity, Vision, AVFoundation, Foundation Models, CryptoKit, CoreLocation) — no CocoaPods, no npm, no pip.

---

## Toolchain & Platform Requirements

<!-- Verify:
  grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' "Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj" | sort -u
  grep -o 'MACOSX_DEPLOYMENT_TARGET = [0-9.]*' "Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj" | sort -u
  head -1 core/Package.swift
  xcodebuild -version
-->

| Requirement | Value |
|-------------|-------|
| iOS app deployment target | **iOS 26.2** (`IPHONEOS_DEPLOYMENT_TARGET = 26.2`) |
| Mac compatibility path | Mac Catalyst-capable destination via the `WiredPart-iOS` scheme when needed |
| Core package platforms | iOS 17 / macOS 14 (`core/Package.swift`) — the package builds lower than the app so `swift test` runs on more Macs |
| Swift tools version | 6.0 (`// swift-tools-version: 6.0`) |
| Xcode | Xcode 26.2 or newer (needs the iOS 26.2 SDK; repo verified with Xcode 26.5 / build 17F42) |
| macOS host | Apple Silicon Mac recommended (matches the self-hosted CI runner) |

---

## Install / Resolve Commands

```bash
# Resolve and build the core package
cd core
swift package resolve
swift build
swift test

# App: open either entry point and let Xcode resolve packages
open "Weird Parts IOS/Weird Parts.xcodeproj"     # project (schemes: "Weird Parts", "WiredPartCore")
open "Weird Parts.xcworkspace"                    # workspace (schemes: "WiredPart-iOS", Stage-9 smokes, "WiredPartCore", ...)
```

See [SETUP.md](SETUP.md) for full build/test instructions and scheme details.

---

## CI Runner Dependencies

iOS/macOS/Xcode CI jobs run on the repository's local self-hosted Mac runner, not GitHub-hosted macOS runners. Runner identity, labels, and recovery steps live in the canonical runbook: [runbooks/local-mac-actions-runner.md](runbooks/local-mac-actions-runner.md). Do not duplicate machine-specific details here.

Optional local tooling (not build dependencies): GitHub CLI `gh` for PR/runner checks, Python 3 for `scripts/` repo guards.

---

## Dependency Checklist

- [x] `core/Package.resolved` committed and matches `Package.swift` pins — verified 2026-07-01
- [x] GRDB fork pinned exactly (`2.4.2-1`) with rationale documented in `Package.swift` — verified 2026-07-01
- [x] No other third-party package managers in use (no Podfile, no package.json, no requirements.txt) — verified 2026-07-01
- [ ] Any newly introduced package must be documented in this file with a "why" row and a pin policy
