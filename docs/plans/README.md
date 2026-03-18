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
| `estimate_and_risks.md` | Time estimates + risk register (13 risks) |
| `ocr_plan.md` | Document scanning & OCR auto-extraction (Phase 12+) |
| `qr_plan.md` | QR code recognition & auto-fill pipeline (Phase 12+) |
| `image_match_plan.md` | Camera-based part matching (Phase 12+) |
| `text_predict_plan.md` | Intelligent text pre-fill & predictive typing (Phase 12+) |
| `bluetooth_sync_expanded.md` | Expanded BT sync for images & AI data (Phase 12+) |

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
- **Sync:** Multipeer Connectivity (Apple). LAN HTTP (all platforms). Ad-hoc network for Mac-Windows. Chunked binary sync for images (Phase 12+).
- **AI:** Foundation Models (Apple primary). Copilot Runtime (Windows primary). llama.cpp (fallback both).
- **OCR:** Vision framework (Apple). Windows.Media.Ocr (Windows). Platform-agnostic field extraction in Core.
- **QR:** Native camera scanning (DataScanner/AVCapture). V2 schema with 8 entity types. Auto-fill pipeline.
- **Image Matching:** Vision VNFeaturePrint (Apple). MobileNetV3 ONNX (Windows). Cosine similarity search.
- **Predictive Text:** Entity lookup + phrase history + LLM ghost text. 71 Tier-1 fields. Local-only history.
- **Repo:** Monorepo with `/core`, `/mac`, `/ios`, `/windows`, `/src` (legacy).
- **Constraint:** All AI/scanning features operate 100% offline. Bluetooth-only device sync. No cloud APIs.
