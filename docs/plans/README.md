# WiredPart — Plans Directory

> **Last updated:** 2026-03-18
> **Current work:** Dashboard Hub, iOS audit fixes, brand-supplier linking
> **Completed phases:** 1-10 + all gap closures + Tauri migration + production hardening

---

## Project Summary

WiredPart is a construction/trade business management app. Local-first, offline-capable, syncs peer-to-peer over Bluetooth and Wi-Fi. Runs on iOS (iPhone + iPad), macOS, and Windows via shared core package.

**Stats:** ~160 Swift files (iOS) + 50 core files | 23 migrations, ~130 tables (GRDB/SQLite) | 15 services

---

## Active Plans

| Plan | Status | Description |
|------|--------|-------------|
| `dashboard-hub-plan.md` | **ACTIVE** | Dashboard as user hub: 4 tabs (Overview + clock banner, Clock with GPS-sorted jobs + geofencing, Daily Report command center, Fast QR scanner) |
| `deployment-master-plan.md` | 19/23 | App Store, DMG, NSIS distribution. 4 remaining tasks need physical devices |
| `qr_plan.md` | Reference | QR v2 payload schema, 8 entity types, auto-fill pipeline |

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
| `phase-12-pwa-desktop.md` | Service worker, keyboard shortcuts, command palette |
| `Mobile device bootstrap.md` | App Store shell that downloads real program from shop |
| `windows-architecture.md` | Tauri/React dual-platform, llama.cpp for Windows AI |
| `sideloading-guide.md` | Enterprise distribution without App Store |

## Architecture

- **Sync:** Apple Multipeer Connectivity (BT/Wi-Fi P2P) + LAN HTTP. LWW + field-level merge. Ed25519 device trust. Vector clocks.
- **AI:** Foundation Models (Apple), llama.cpp (Windows), no cloud. On-device only.
- **QR:** VisionKit DataScannerViewController. V2 schema with 8 entity types. Auto-fill pipeline.
- **Constraint:** Everything offline. Bluetooth-only sync. No cloud APIs.

## Completed Phase History

All completed plans archived in `archive/`. Phases 1→10, Tauri migration, production hardening, testing strategy, all gap closures — all done.

## Build & Test

```bash
# Core package
cd core && swift build && swift test

# iOS app (Xcode)
# Open Wierd Parts.xcworkspace, select WiredPart-iOS scheme, Cmd+B
```
