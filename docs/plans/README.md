# WiredPart — Plans Directory

> **Last updated:** 2026-05-26
> **Current authority:** `staged-paperclip-goals.md`
> **Active Paperclip stage:** Stage 1, app shell, identity, local DB, onboarding, and navigation

---

## Project Summary

WiredPart is a local-first construction/trade business management app. The current beta target is the native iOS app with a shared Swift core package. Historical Tauri, React, macOS, and Windows plans remain useful background, but they are not active beta scope unless a current GitHub/Paperclip issue explicitly reactivates them.

**Current posture:** SwiftUI iOS app + shared Swift core package, GRDB/SQLite, Apple Multipeer Connectivity sync, Apple Foundation Models integration, and beta-readiness work across the 14 product areas listed in `docs/paperclip-handoff.md`.

---

## Active Plans

| Plan | Status | Description |
|------|--------|-------------|
| `paperclip-agentic-execution-loop.md` | **ACTIVE** | Goal -> repo plan -> GitHub issue -> Paperclip issue -> PR/CI/merge -> closeout routing rules for autonomous execution |
| `staged-paperclip-goals.md` | **ACTIVE AUTHORITY** | Dependency-first Paperclip execution index: north star, Stage 1 active focus, Stages 2-10 planned, `[R]` required dependencies, high-priority report exports, promotion rule, quality gates, and GitHub/backlog handles. |
| `dashboard-hub-plan.md` | Planned | Dashboard as user hub: 4 tabs. Do not treat as active implementation until its stage is promoted. |
| `deployment-master-plan.md` | Planned | App Store, DMG, NSIS distribution. 4 remaining tasks need physical devices; execution waits for the deployment stage. |
| `qr_plan.md` | Reference | QR v2 payload schema, 8 entity types, auto-fill pipeline |

Historical plan files may say "active" or "current" based on older sessions. For Paperclip execution, `staged-paperclip-goals.md` wins.

## Paperclip / GitHub Routing

Use `paperclip-agentic-execution-loop.md` before creating or delegating autonomous engineering work. It defines:

- Required GitHub issue fields: field-test relevance, labels, acceptance criteria, repo plan link, Paperclip link, and verification.
- Required Paperclip child issue fields: owner lane, repo/project, exact scope, acceptance criteria, required evidence, review lane, and pass-up trigger.
- Branch/worktree hygiene preflight before opening new Weird Parts coding work.
- Closeout evidence expected for PRs, CI, worktree cleanup, and Paperclip status comments.

## Future Plans (Designed, Not Started)

| Plan | Description |
|------|-------------|
| `bluetooth_sync_expanded.md` | Extended BT sync for AI data, chunked binary transfer (16KB frames), priority system |
| `phase-13-sync-bluetooth.md` | Full BT mesh protocol, gossip, PGP encryption, device pairing |
| `phase-14-ai-integration.md` | Local LLM, NL queries, anomaly detection, predictive ordering |
| `phase-15-remote-sync.md` | **ON HOLD** — internet sync, shop-to-shop, shared channels |
| `phase-16-ux-polish-and-admin-hub.md` | Nav restructure, warehouse enhancements, teams, device mgmt |
| `apple-foundation-models-integration.md` | Apple Foundation Models (macOS 26+), on-device AI, tool use |
| `ai-assistant-plan.md` | AI assistant panel, text prediction, contextual suggestions |
| `supplier-communication-bridge-plan.md` | Supplier portal, PO acknowledgments, delivery tracking |
| `phase-12-pwa-desktop.md` | Historical/reference unless reactivated by a current beta issue |
| `Mobile device bootstrap.md` | Historical/reference unless reactivated by a current beta issue |
| `windows-architecture.md` | Historical/reference unless reactivated by a current beta issue |
| `sideloading-guide.md` | Enterprise distribution without App Store |

## Architecture

- **Sync:** Apple Multipeer Connectivity (BT/Wi-Fi P2P) + LAN HTTP. LWW + field-level merge. Ed25519 device trust. Vector clocks.
- **AI:** Foundation Models (Apple). Historical Windows/local-LLM plans are reference only unless reactivated.
- **QR:** VisionKit DataScannerViewController. V2 schema with 8 entity types. Auto-fill pipeline.
- **Constraint:** Everything offline. Bluetooth-only sync. No cloud APIs.

## Completed Phase History

Completed and inactive plans are archived in `archive/` or retained as reference plans. Treat pre-iOS-native architecture plans as historical unless a current issue links them as active scope.

## Build & Test

```bash
# Core package
cd core && swift build && swift test

# iOS app (Xcode)
# Open Wierd Parts.xcworkspace, select WiredPart-iOS scheme, Cmd+B
```
