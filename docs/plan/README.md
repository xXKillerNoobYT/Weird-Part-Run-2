# WiredPart Native SwiftUI Migration — Plan Directory

> **Created:** 2026-03-14
> **Master plan:** See `swiftui-native-migration-plan.md` in `docs/plans/`

## Overview

This directory contains the detailed planning artifacts for migrating WiredPart from a Tauri/React WebView architecture to full native SwiftUI (macOS/iOS) with a shared Swift core package.

## Plan Files

| File | Purpose |
|------|---------|
| `README.md` | This file — overview and how to build/test |
| `repo_map.md` | Current repo structure mapped to target structure |
| `core_boundary.md` | All modules in WiredPartCore with function/class lists |
| `adapters.md` | Platform adapter interfaces (sync, AI, filesystem) |
| `ui_flow.md` | Page-by-page flow map for macOS and iOS |
| `ai_agent_checks.md` | Cross-platform validation checks and thresholds |
| `test_matrix.md` | Full test matrix table |
| `file_staging_list.md` | Every file to create/modify/delete with patch sketches |
| `branching_and_rollback.md` | Branch naming, commit template, rollback steps |
| `estimate_and_risks.md` | Time estimates + risk register |

## How to Build & Test (Per Platform)

### Swift Core Package (all platforms)

```bash
cd core/
swift build          # compile the package
swift test           # run all unit tests (in-memory SQLite)
```

### macOS App (Xcode)

1. Open `mac/WiredPartMac.xcodeproj` in Xcode
2. Select the `WiredPartMac` scheme
3. Build: Cmd+B
4. Run: Cmd+R
5. Test: Cmd+U (runs XCUITest suite)

### iOS App (Xcode)

1. Open `ios/WiredPartIOS.xcodeproj` in Xcode
2. Select `WiredPartIOS` scheme and a simulator
3. Build: Cmd+B
4. Run: Cmd+R
5. Test: Cmd+U

### Legacy Tauri App (unchanged during migration)

```bash
# Frontend dev
npm run dev

# Tauri desktop
cd src-tauri && cargo tauri dev

# Tauri iOS
cd src-tauri && cargo tauri ios dev
```

### Running Tests

```bash
# Core package unit tests (fast, in-memory)
cd core && swift test

# macOS UI tests
xcodebuild test -project mac/WiredPartMac.xcodeproj -scheme WiredPartMac -destination 'platform=macOS'

# iOS UI tests
xcodebuild test -project ios/WiredPartIOS.xcodeproj -scheme WiredPartIOS -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture Decisions

- **UI:** Full native SwiftUI (macOS/iOS). React WebView as interim fallback.
- **Core:** `WiredPartCore` Swift package — GRDB/SQLite, business logic, sync engine.
- **Sync:** Multipeer Connectivity (Apple). LAN HTTP (all platforms). Ad-hoc network for Mac-Windows.
- **AI:** Foundation Models (Apple primary). Copilot Runtime (Windows primary). llama.cpp (fallback both).
- **Repo:** Monorepo with `/core`, `/mac`, `/ios`, `/windows`, `/src` (legacy).
