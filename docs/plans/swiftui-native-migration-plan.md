# WiredPart: Full Native SwiftUI Migration Plan

**Status:** Planning — awaiting user approval
**Created:** 2026-03-14
**Scope:** Migrate from Tauri/React WebView to native SwiftUI (macOS/iOS), shared Swift core, Windows native later

---

## Decisions Summary

| Decision | Choice |
|----------|--------|
| **UI** | Full native SwiftUI for macOS/iOS. React WebView kept as interim fallback during page-by-page migration. |
| **Shared core** | `WiredPartCore` Swift package — models, persistence (GRDB/SQLite), business logic, sync engine. |
| **Sync** | Apple keeps Multipeer Connectivity. Windows uses LAN HTTP only. Ad-hoc network for Mac↔Windows when no shared LAN (user-initiated). |
| **AI primary** | Apple Foundation Models (macOS/iOS). Windows Copilot Runtime. |
| **AI fallback** | llama.cpp on both platforms for tasks native AI can't do, or when native AI unavailable. User toggle in Settings. |
| **Repo** | Monorepo: `/core` (Swift package), `/mac` (SwiftUI macOS), `/ios` (SwiftUI iOS), `/windows` (later), `/src` (React legacy, sunset incrementally) |

---

## Target Monorepo Structure

```
/
├── core/                          # WiredPartCore Swift Package
│   ├── Package.swift
│   ├── Sources/WiredPartCore/
│   │   ├── Database/              # GRDB layer, migrations, BaseRepository
│   │   ├── Models/                # All Swift data model structs
│   │   ├── Services/              # Business logic (36+ service equivalents)
│   │   ├── Sync/                  # LAN HTTP + Multipeer sync engine
│   │   ├── Crypto/                # Ed25519 via CryptoKit
│   │   └── AI/                    # Foundation Models + llama.cpp
│   └── Tests/WiredPartCoreTests/
├── mac/                           # SwiftUI macOS App
│   ├── WiredPartMac/
│   │   ├── App/                   # Entry, AppDelegate, environment
│   │   ├── Navigation/            # Sidebar, tab structure
│   │   ├── Features/              # 14 feature modules (SwiftUI views)
│   │   ├── WebFallback/           # WKWebView for unported pages
│   │   └── Theme/                 # Colors, fonts, design tokens
│   └── WiredPartMacTests/
├── ios/                           # SwiftUI iOS App
│   ├── WiredPartIOS/
│   │   ├── App/
│   │   ├── Navigation/            # Tab bar
│   │   └── Features/              # iOS-adapted views
│   └── WiredPartIOSTests/
├── windows/                       # Windows app (Phase 14)
├── src/                           # React legacy (sunset incrementally)
├── src-tauri/                     # Tauri Rust shell (retired Phase 15)
├── backend/                       # Python FastAPI shop server (unchanged)
└── docs/plan/                     # Plan artifacts
```

---

## Phase Overview

| Phase | Name | Effort | What It Delivers |
|-------|------|--------|-----------------|
| 1 | Swift Core Package | High | `WiredPartCore` — DB, models, base repo, change tracker, auth, settings. 50+ unit tests. |
| 2 | Sync Engine | High | LAN sync server (swift-nio), mDNS (NWBrowser), Multipeer (native Swift), conflict resolver, crypto. |
| 3 | macOS/iOS App Shell | Medium | SwiftUI app with sidebar nav, WebView fallback router, auth flow, theme system. |
| 4 | Dashboard + Settings | Medium | First 2 modules native. Proves the full pattern: SwiftUI ↔ Core ↔ SQLite. |
| 5 | Parts & Inventory | High | 10 pages: catalog, categories tree, brands, suppliers, pricing, companions, forecasting, import/export. |
| 6 | Warehouse | High | 9 pages: dashboard, movements, staging, receiving (native QR scanner), returns, audit, network. |
| 7 | Jobs & Labor | High | 6 pages: active jobs, detail, clock in/out (CoreLocation GPS), questionnaire, daily reports. |
| 8 | Orders & Procurement | High | 12 pages: unified order, POs, JPOs, procurement, returns. PDFKit for PDF generation. |
| 9 | People & Contacts | High | 10 pages: employees, customers, contractors, contacts, teams, hats, permissions. |
| 10 | Scheduling | High | 7 pages: calendar grid, dispatch, templates, config, time off, availability, sub-schedule. |
| 11 | Remaining Modules | High | 24 pages: fleet(6), tools(4), chat(3), notebooks(3), reports(4), office(4). |
| 12 | AI — Apple | High | Foundation Models direct Swift (no FFI bridge), llama.cpp fallback, AI text fields, enhance popover. |
| 13 | AI — Windows | Medium | Windows Copilot Runtime primary, llama.cpp fallback. |
| 14 | Windows Target | High | Evaluate Swift on Windows. If viable: same core. If not: WinUI 3 + C interop or keep Tauri/React. |
| 15 | Cleanup | Low | Remove `src-tauri/`, `src/`, Tauri config. Final repo: core + mac + ios + windows. |

---

## Phase 1: Foundation — Swift Core Package

### Summary
Create `WiredPartCore`, the shared Swift package consumed by all Apple platform targets. Pure Swift with no UIKit/SwiftUI deps — only Foundation, GRDB.swift (SQLite ORM), CryptoKit. Testable on any platform. This is the foundation everything else depends on.

### Tasks

**1.1 — Create Package.swift scaffold**
- Path: `core/Package.swift`
- Products: `WiredPartCore` library
- Dependencies: `groue/GRDB.swift` (type-safe SQLite, migrations, observation)
- Acceptance: `swift build` succeeds

**1.2 — Port 17 SQLite migrations**
- Path: `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- Ported from: `src/local/migrations/` (001–017)
- GRDB `DatabaseMigrator` with one registered migration per file
- Tests: `DatabaseTests.swift` — all 17 apply to in-memory DB, table/index existence verified
- Acceptance: Schema is column-identical to TypeScript migration output

**1.3 — Port all data models**
- Path: `core/Sources/WiredPartCore/Models/` (one file per domain)
- Ported from: TypeScript interfaces in `src/local/services/*.ts`
- Swift structs conforming to `Codable, FetchableRecord, PersistableRecord`
- Domains: Foundation (User, Hat, Device, Setting), Parts, Jobs, Orders, Fleet, People, Scheduling, Chat, Sync
- Tests: `ModelTests.swift` — Codable round-trip, insert+fetch equality
- Acceptance: Every TS interface has a corresponding Swift struct with matching column names

**1.4 — Port BaseRepository + ChangeTracker**
- Path: `core/Sources/WiredPartCore/Database/BaseRepository.swift`, `Sync/ChangeTracker.swift`
- Ported from: `src/local/repos/base-repo.ts`, `src/local/change-tracker.ts`
- All writes auto-call `trackChange()` — writes to `_change_log`
- Tests: Insert User → verify change log entry; Update email → verify UPDATE with `changed_fields`
- Acceptance: No write can bypass change tracking

**1.5 — Port auth service**
- Path: `core/Sources/WiredPartCore/Services/AuthService.swift`
- Ported from: `src/local/services/auth-service.ts`
- PIN auth, user picker, seed first admin, permissions check
- PIN hashing: CryptoKit SHA256 (compatible with existing DB hashes)
- Tests: `AuthServiceTests.swift` — seed admin, auth correct PIN, reject wrong PIN, verify permissions
- Acceptance: Auth flow works end-to-end in tests

**1.6 — Port settings service (core subset)**
- Path: `core/Sources/WiredPartCore/Services/SettingsService.swift`
- Get/set settings, theme, company profile
- Tests: `SettingsServiceTests.swift`

**1.7 — Phase 1 test suite**
- Target: 50+ unit tests, all in-memory
- Files: `DatabaseTests`, `ModelTests`, `AuthServiceTests`, `ChangeTrackerTests`, `SettingsServiceTests`

---

## Phase 2: Sync Engine

### Summary
Port the entire sync infrastructure to pure Swift. Replaces: axum HTTP server (Rust), mdns-sd (Rust), MultipeerBridge (ObjC), ed25519-dalek (Rust), sync-engine.ts + peer-manager.ts + conflict-resolver.ts (TypeScript).

### Tasks

**2.1 — Conflict resolver** → `core/.../Sync/ConflictResolver.swift`
- Ported from: `src/local/conflict-resolver.ts` (500 lines)
- LWW per-field, field-level merge, `_conflict_log` writes

**2.2 — Change tracker (full API)** → extend `ChangeTracker.swift`
- `getPendingChanges()`, `markSynced()`, `pruneOldChanges()`, vector clock operations

**2.3 — Ed25519 crypto** → `core/.../Crypto/SyncCrypto.swift`
- Ported from: `src-tauri/src/crypto.rs`
- CryptoKit `Curve25519.Signing` replaces `ed25519-dalek`

**2.4 — LAN sync server** → `core/.../Sync/LanSyncServer.swift`
- Ported from: `src-tauri/src/sync_server.rs`
- swift-nio HTTP server on ephemeral port
- Endpoints: `POST /sync/push`, `POST /sync/pull`, `GET /sync/status`
- **Critical:** JSON format must be backward-compatible with TypeScript peer-manager

**2.5 — mDNS discovery** → `core/.../Sync/PeerDiscovery.swift`
- Ported from: `src-tauri/src/discovery.rs`
- `NWBrowser`/`NWListener` from Network.framework
- Service: `_wiredpart._tcp`
- `@Published` peers for SwiftUI binding

**2.6 — Multipeer Connectivity (native Swift)** → `core/.../Sync/MultipeerManager.swift`
- Ported from: `src-tauri/objc/MultipeerBridge.m` + `src-tauri/src/multipeer.rs`
- Direct `MCSession`/`MCBrowser`/`MCAdvertiser` — no ObjC bridge needed
- Same-company auto-invite, `MCEncryptionRequired`

**2.7 — Sync engine actor** → `core/.../Sync/SyncEngine.swift`
- Ported from: `src/local/sync-engine.ts`
- Swift actor (replaces `syncLock` boolean)
- `NWPathMonitor` for network change observation
- Periodic sync, exponential backoff, initial sync

**2.8 — Peer manager** → `core/.../Sync/PeerManager.swift`
- Coordinates PeerDiscovery + MultipeerManager + SyncEngine

**2.9 — Integration tests**
- Push/pull on loopback, LWW conflict, vector clock delta, initial sync
- Shared JSON fixture tests (verify Swift server handles TypeScript client format)

---

## Phase 3: macOS/iOS App Shell

### Summary
SwiftUI app targets for macOS and iOS. Sidebar navigation, WebView fallback for unported pages, auth flow, theme system. The key mechanism: `NavigationRouter` decides native view vs WebView per route.

### Tasks

**3.1 — Create `mac/` Xcode project** — macOS 14.0+, links WiredPartCore
**3.2 — App entry + environment** — `WiredPartMacApp.swift`, `AppCore` observable
**3.3 — Sidebar navigation** — 14 modules matching current AppShell
**3.4 — WebView fallback router** — `WKWebView` loads React dist; auth token injected via JS
**3.5 — Theme system** — dark/light/system from GRDB settings
**3.6 — Auth flow** — login view, PIN pad, bootstrap view
**3.7 — iOS app target** — tab bar nav, same WebFallback, same auth

**Note on Mac↔Windows sync:** When not on a shared LAN, Windows can create a Wi-Fi hotspot that the Mac joins for a user-initiated sync session. This is LAN HTTP sync over the hotspot's local network — no protocol changes needed, just a Settings UI for "Connect to Windows sync network."

---

## Phases 4–11: Feature Module Migration

Each phase ports one module from React to SwiftUI. Pattern per module:
1. Port TypeScript services to Swift (add to `core/Sources/WiredPartCore/Services/`)
2. Build SwiftUI views (add to `mac/WiredPartMac/Features/`)
3. Update `NavigationRouter` to route module to native views
4. Write unit tests for services, UI tests for views
5. Retire WebFallback for that module's routes

### Phase 4: Dashboard + Settings (medium, 22+ pages)
### Phase 5: Parts & Inventory (high, 10 pages, category tree)
### Phase 6: Warehouse (high, 9 pages, native QR via DataScannerViewController)
### Phase 7: Jobs & Labor (high, 6 pages, CoreLocation GPS, BackgroundTasks)
### Phase 8: Orders & Procurement (high, 12 pages, PDFKit generation)
### Phase 9: People & Contacts (high, 10 pages)
### Phase 10: Scheduling (high, 7 pages, calendar drag-drop grid)
### Phase 11: Fleet + Tools + Chat + Notebooks + Reports + Office (high, 24 pages)

---

## Phase 12: AI Integration (Apple)

### Summary
With SwiftUI migration complete, Foundation Models is called directly from Swift — no Rust FFI, no TypeScript polling, no C string marshaling. llama.cpp as Swift package for fallback.

### Tasks
- **12.1** — `FoundationModelsService` actor (direct `LanguageModelSession` async/await)
- **12.2** — llama.cpp Swift package integration (GGUF model download, same protocol)
- **12.3** — SwiftUI AI components: `AITextField`, `EnhancePopover`, `AIPrefillBanner`
- **12.4** — Wire AI fields into all 71 Tier-1 text fields
- **12.5** — Custom tools (SearchParts, SearchContacts, etc.) using GRDB queries directly

---

## Phase 13–14: Windows

- **Phase 13:** Windows Copilot Runtime + llama.cpp fallback
- **Phase 14:** Evaluate Swift on Windows maturity. If viable: same WiredPartCore. If not: WinUI 3 + C interop or keep Tauri/React for Windows. LAN sync only (no Multipeer).

---

## Phase 15: Cleanup

Remove `src-tauri/`, `src/`, `index.html`, `vite.config.ts`, `package.json`, `node_modules/`, Capacitor artifacts. Final repo: `core/` + `mac/` + `ios/` + `windows/` + `backend/` + `docs/`.

---

## Cross-Platform File Mapping (Key Files)

| Current (TypeScript/Rust/ObjC) | New (Swift) | Phase |
|------|------|-------|
| `src/local/db.ts` + `db-config.ts` | `core/.../Database/AppDatabase.swift` | 1 |
| `src/local/migrations/*` | `core/.../Database/AppDatabase+Migrations.swift` | 1 |
| `src/local/repos/base-repo.ts` | `core/.../Database/BaseRepository.swift` | 1 |
| `src/local/change-tracker.ts` | `core/.../Sync/ChangeTracker.swift` | 1–2 |
| `src/local/conflict-resolver.ts` | `core/.../Sync/ConflictResolver.swift` | 2 |
| `src/local/sync-engine.ts` | `core/.../Sync/SyncEngine.swift` | 2 |
| `src/local/peer-manager.ts` | `core/.../Sync/PeerManager.swift` | 2 |
| `src-tauri/src/sync_server.rs` | `core/.../Sync/LanSyncServer.swift` | 2 |
| `src-tauri/src/discovery.rs` | `core/.../Sync/PeerDiscovery.swift` | 2 |
| `src-tauri/src/crypto.rs` | `core/.../Crypto/SyncCrypto.swift` | 2 |
| `src-tauri/objc/MultipeerBridge.m` + `src-tauri/src/multipeer.rs` | `core/.../Sync/MultipeerManager.swift` | 2 |
| `src-tauri/swift/FoundationModelsBridge.swift` + `foundation_models.rs` | `core/.../AI/FoundationModelsService.swift` | 12 |
| `src/local/services/auth-service.ts` | `core/.../Services/AuthService.swift` | 1 |
| `src/local/services/*-service.ts` (36 files) | `core/.../Services/*.swift` | 1–11 |
| `src/features/*/pages/*.tsx` (86 pages) | `mac/WiredPartMac/Features/*/*.swift` | 4–11 |
| `src/lib/environment.ts` | Not needed — Swift `#if os()` / `ProcessInfo` | 3 |
| `src/lib/foundation-models.ts` | `core/.../AI/FoundationModelsService.swift` | 12 |

---

## Test Matrix

| Test Type | Core (Swift) | macOS (SwiftUI) | iOS (SwiftUI) | Windows |
|-----------|-------------|-----------------|---------------|---------|
| **Build success** | `swift build` | Xcode build | Xcode build | TBD Phase 14 |
| **Unit tests** | 200+ via `swift test` | — | — | — |
| **Integration (sync)** | Push/pull loopback, conflict res | — | — | — |
| **UI navigation** | — | XCUITest all 14 modules | XCUITest all tabs | TBD |
| **Menu/sidebar parity** | — | Sidebar matches spec | Tab bar matches spec | TBD |
| **Persistence r/w** | GRDB CRUD tests | Settings persist across restart | Same | TBD |
| **AI deterministic** | 3 canonical prompts, expected output tolerance | AI field components | Same | Copilot Runtime |
| **Resource usage** | — | Instruments: <200MB RSS, <5% idle CPU | Same | TBD |
| **Cold start** | — | <3s to first paint | <2s to first paint | TBD |
| **Error/offline** | — | No crash on airplane mode | Same | Same |
| **BT sync** | MultipeerManager two-instance | Peer discovery test | Same | N/A (LAN only) |

### 3 Canonical AI Prompts for Behavior Tests

1. **Autocomplete:** Input: `"The delivery for job 1234 was del"` → Expected: completion continuing the sentence naturally (e.g., `"ayed due to..."` or `"ivered on time"`)
2. **Enhance (proofread):** Input: `"recived parts form supplyer, wil inspect tomorow"` → Expected: corrected spelling, grammar preserved meaning
3. **Pre-fill (dispatch notes):** Context: `{jobName: "Smith Renovation", crewLead: "Mike", date: "2026-03-15"}` → Expected: generated dispatch note mentioning job, crew, and date

---

## Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| 1 | GRDB schema drift from TS migrations | High | High | Automated schema comparison tool; CI check before Phase 1 complete |
| 2 | Sync protocol break between TS and Swift during transition | Medium | High | Formal JSON schema doc; shared fixture tests; keep Tauri running until all devices updated |
| 3 | WKWebView auth bridge breaks sessions | Medium | Medium | JS eval injects auth token into WebView localStorage; test on all supported OS versions |
| 4 | Swift NIO server behaves differently from axum | Medium | Medium | Integration tests against TS peer-manager; keep Rust server as reference |
| 5 | Foundation Models SDK not yet released | High | Low | Phase 12 decoupled; existing Tauri bridge continues; llama.cpp fallback |
| 6 | SQLite WAL conflicts during transition (both apps open same DB) | Low | High | OS enforces single app; document constraint; never run both simultaneously |
| 7 | Windows becomes permanently second-class | Medium | Medium | Phase 14 time-boxed; explicit decision between Swift-on-Windows vs WinUI3 vs keep-Tauri |
| 8 | BT sync edge cases (pairing failures, data conflicts) | Medium | Medium | Exhaustive MultipeerManager tests; conflict resolution already battle-tested in TS; port tests too |

---

## Branching Strategy

- **Branch naming:** `phase/<N>-<short-desc>` (e.g., `phase/1-swift-core`)
- **Feature branches:** `feat/<phase>.<task>-<desc>` (e.g., `feat/1.2-migrations`)
- **Commit template:** `feat: <summary> — files: <paths> — tests: <test paths>`
- **Staging order:** core → sync → app shell → features (one at a time) → AI → Windows → cleanup
- **Pre-merge:** `swift build` + `swift test` + Xcode build (mac + iOS) must pass
- **Main branch:** always ships the existing Tauri app. New Swift code is additive until Phase 15.

---

## Rollback Plan

Each phase is additive (new `/core`, `/mac`, `/ios` directories). The existing `src/` and `src-tauri/` are never modified until Phase 15.

- **To roll back any phase:** delete the new Swift files added in that phase. The Tauri app on `main` continues to work.
- **Phase 15 rollback:** `git revert` the cleanup commit. `src/` and `src-tauri/` are restored from git history.
- **Local-only guarantee:** No network calls during runtime except LAN sync (HTTP) and Multipeer (BT/Wi-Fi P2P). Validated by: no `URLSession` calls to external hosts; runtime network monitor in debug builds.

---

## Sign-Off Checklist (Final)

- [ ] `docs/plan/repo_map.md` created and accurate
- [ ] `docs/plan/core_boundary.md` lists all core modules
- [ ] `docs/plan/ui_flow.md` shows every screen and menu parity
- [ ] File staging plan produced for every planned change
- [ ] Test matrix completed with pass criteria
- [ ] Branching and rollback plan documented
- [ ] Risk register reviewed and mitigations accepted
- [ ] Effort estimates reviewed

---

## Estimated Duration

18–24 months with one experienced SwiftUI developer. 9–12 months with a two-person team. Phases 1–3 are sequential prerequisites. Phases 4–11 can partially overlap (one module at a time). Phases 12–14 can run in parallel with later feature phases.

---

## Verification Strategy

After each phase:
1. Run `swift build` and `swift test` for the core package
2. Build macOS and iOS targets in Xcode
3. Run XCUITest suite for all ported modules
4. Manual smoke test: navigate every native page, verify data persists, verify sync works
5. Verify WebFallback still works for unported pages
6. Check that the existing Tauri app on `main` is unaffected

---

## Plan File Artifacts (to be created in docs/plan/)

| File | Content |
|------|---------|
| `docs/plan/README.md` | Overview, how to build/test on each platform |
| `docs/plan/repo_map.md` | Current repo structure mapped to target structure |
| `docs/plan/core_boundary.md` | All modules in WiredPartCore with function lists |
| `docs/plan/adapters.md` | Platform adapter interfaces (sync, AI, filesystem) |
| `docs/plan/ui_flow.md` | Page-by-page flow map for macOS and iOS |
| `docs/plan/ai_agent_checks.md` | Cross-platform validation checks and thresholds |
| `docs/plan/test_matrix.md` | Full test matrix table |
| `docs/plan/file_staging_list.md` | Every file to create/modify/delete with patch sketches |
| `docs/plan/branching_and_rollback.md` | Branch naming, commit template, rollback steps |
| `docs/plan/estimate_and_risks.md` | Time estimates + risk register |
