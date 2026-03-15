# Estimates and Risk Register

> Time estimates per phase and the top 8 risks with mitigations.

---

## Time Estimates Per Phase

| Phase | Name | Effort | Scope |
|-------|------|--------|-------|
| 1 | Swift Core Package | High | Package.swift, 17 migrations, ~50 model structs, BaseRepository, ChangeTracker, AuthService, SettingsService, 50+ unit tests |
| 2 | Sync Engine | High | ConflictResolver, LanSyncServer (swift-nio), PeerDiscovery (NWBrowser), MultipeerManager (native Swift), SyncEngine actor, SyncCrypto, 20+ integration tests |
| 3 | macOS/iOS App Shell | Medium | Xcode projects, sidebar nav, WebView fallback, auth flow, theme system, iOS tab bar |
| 4 | Dashboard + Settings | Medium | DashboardService, 10+ Settings pages, GRDB observation, theme persistence |
| 5 | Parts & Inventory | High | 9 sub-services, 10 pages, category tree (OutlineGroup), import/export |
| 6 | Warehouse | High | 3 services, 9 pages, QR scanner (DataScannerViewController), movement wizard |
| 7 | Jobs & Labor | High | 2 services, 6 pages, CoreLocation GPS, clock-in flow, questionnaire |
| 8 | Orders & Procurement | High | 2 services, 12 pages, unified order form, PDFKit generation |
| 9 | People & Contacts | High | 3+ services, 10 pages, volume of views |
| 10 | Scheduling | High | 2 services, 7 pages, calendar grid, drag-and-drop |
| 11 | Remaining Modules | High | 6 modules, 24 pages, 6+ services |
| 12 | AI — Apple | High | FoundationModelsService, LlamaCppService, AITextField, EnhancePopover, 71 field integrations |
| 12+ | AI-Assisted Capabilities | High | OCRProcessor, QRCodec/QRGenerator, ImageMatcher, TextPredictor, BinarySyncManager, platform adapters (OCR, QR, ImageFeature), CameraMatchView, DocumentScanView, AutoFillBanner, ~30 new files, ~50 new tests |
| 13 | AI — Windows | Medium | CopilotRuntimeService, llama.cpp on Windows |
| 14 | Windows Target | High | Platform evaluation, app target creation, testing |
| 15 | Cleanup | Low | Delete src/, src-tauri/, update docs |

### Duration Estimates

**Solo developer (1 experienced SwiftUI engineer):**
- Phases 1–3 (foundation): 3–4 months
- Phases 4–11 (feature migration): 10–14 months
- Phase 12 (AI core): 1–2 months
- Phase 12+ (AI-assisted capabilities): 2–3 months
- Phases 13–14 (Windows): 2–3 months
- Phase 15 (cleanup): 1 week
- **Total: 20–27 months**

**Two-person team:**
- Phases 1–3: 2–3 months (sequential, hard to parallelize)
- Phases 4–11: 5–7 months (one person on services, one on views)
- Phase 12 + 12+: 2–3 months (parallelizable: one on core AI, one on OCR/QR/image)
- Phases 13–14: 1–2 months
- **Total: 10–14 months**

---

## Risk Register

### Risk 1: GRDB Schema Drift from TypeScript Migrations

| Attribute | Value |
|-----------|-------|
| **Likelihood** | High |
| **Impact** | High (data corruption if schema diverges between platforms) |
| **Description** | 17 migrations with dozens of tables and hundreds of columns. Manual translation from TypeScript SQL to GRDB creates opportunities for typos, missing columns, wrong types, or missing constraints. |
| **Mitigation** | 1. Build an automated `SchemaComparisonTool.swift` that opens a pre-built TS SQLite DB and a fresh GRDB DB, compares every table/column/index/trigger. 2. Run this as a CI gate — Phase 1 cannot merge until schema comparison passes. 3. Keep the TypeScript migration files as reference (don't delete until Phase 15). |
| **Owner** | Phase 1, Task 1.2 |
| **Status** | Open |

### Risk 2: Sync Protocol Break During Mixed-Version Transition

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | High (data loss or sync failure when devices run different versions) |
| **Description** | During the migration, some devices will run the Tauri/React app (TypeScript sync engine) while others run the native Swift app (Swift sync engine). The JSON wire format for push/pull must be identical. Any divergence means sync silently fails or corrupts data. |
| **Mitigation** | 1. Define a formal JSON schema document for sync messages (push request, pull response, change entry). 2. Write shared JSON fixture files that both TypeScript and Swift parse. 3. Run cross-implementation round-trip tests: Swift server → TS client and TS server → Swift client. 4. Keep Tauri app running on `main` until all field devices are updated. |
| **Owner** | Phase 2, Task 2.4 |
| **Status** | Open |

### Risk 3: WKWebView Auth Bridge Failures

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Medium (users forced to re-login when navigating between native and WebView) |
| **Description** | During the transition (Phases 3–14), some pages are native SwiftUI and others load in a WKWebView showing the React app. Auth state must bridge: after native login, the session token must be injected into the WebView's localStorage so React picks up the session. This is fragile — WKWebView security policies, cookie partitioning, and iOS sandboxing can interfere. |
| **Mitigation** | 1. Inject auth via `evaluateJavaScript("localStorage.setItem('wiredpart_auth', ...)")` before first page load. 2. Implement a "re-inject auth" recovery mechanism if WebView loses session. 3. Test on every macOS and iOS version in the support matrix. 4. Consider using `WKUserScript` injected at document start for reliability. |
| **Owner** | Phase 3, Task 3.4 |
| **Status** | Open |

### Risk 4: Swift NIO Server Behavioral Differences from Axum

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Medium (sync failures, data inconsistency) |
| **Description** | The Rust axum HTTP server is battle-tested. Replacing it with a swift-nio HTTP server introduces potential differences in: request parsing, JSON handling, content-type negotiation, error responses, connection timeouts, and concurrent request handling. |
| **Mitigation** | 1. Use `swift-nio` + `swift-nio-http1` rather than hand-rolled HTTP parsing. 2. Write integration tests that replay real sync traffic captured from the Rust server. 3. Keep the Rust sync_server.rs as reference during development. 4. Test with the TypeScript peer-manager as a real client. |
| **Owner** | Phase 2, Task 2.4 |
| **Status** | Open |

### Risk 5: Foundation Models SDK Availability Timing

| Attribute | Value |
|-----------|-------|
| **Likelihood** | High (iOS 26 / macOS 26 not yet released) |
| **Impact** | Low (Phase 12 can be delayed without affecting Phases 1–11) |
| **Description** | Foundation Models requires iOS 26 / macOS 26, which ships fall 2026. Phase 12 cannot be fully tested until the SDK is available. The beta SDK may have bugs or API changes. |
| **Mitigation** | 1. Phase 12 is fully decoupled from Phases 1–11. 2. The existing Tauri Foundation Models bridge continues working for Tauri users. 3. llama.cpp fallback provides AI features on older OS. 4. Use `#if canImport(FoundationModels)` + `@available` guards so the app compiles and runs on all OS versions. |
| **Owner** | Phase 12 |
| **Status** | Open |

### Risk 6: SQLite WAL Conflicts During Transition

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Low |
| **Impact** | High (database corruption) |
| **Description** | If a user accidentally runs both the Tauri app and the new native app simultaneously on the same device, both would try to open the same SQLite database file. While SQLite's WAL mode handles concurrent reads, two separate process writing to the same WAL can cause corruption. |
| **Mitigation** | 1. The native app and Tauri app use different bundle IDs, so macOS treats them as separate apps. 2. Add a file lock (`flock()`) in both `AppDatabase` and `db.ts` — if the DB is locked, show "Database in use by another WiredPart instance" error. 3. Document: never run both apps simultaneously. 4. Phase 15 removes the Tauri app entirely. |
| **Owner** | Phase 3 |
| **Status** | Open |

### Risk 7: Windows Becomes Permanently Second-Class

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Medium (shop computers may be Windows) |
| **Description** | Development effort concentrates on Apple platforms. If Swift on Windows is not mature enough at Phase 14 time, Windows may be stuck on the Tauri/React app indefinitely, creating a permanent maintenance burden of two separate frontends. |
| **Mitigation** | 1. Phase 14 is time-boxed: evaluate Swift on Windows viability within a fixed period. 2. If not viable, make an explicit decision: (a) WinUI 3 native app consuming Core via C FFI, (b) keep Tauri/React for Windows and maintain it, or (c) drop Windows support. 3. Document the decision so future contributors know the chosen path. 4. The Tauri/React app on Windows continues working regardless — it's not broken by the Apple native migration. |
| **Owner** | Phase 14 |
| **Status** | Open |

### Risk 8: Bluetooth Sync Edge Cases

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Medium (sync failures, missed changes) |
| **Description** | Multipeer Connectivity has known quirks: sessions drop under low signal, large transfers can fail silently, background mode is restricted on iOS, and conflict resolution during rapid disconnects/reconnects can create race conditions. Porting from the ObjC bridge to native Swift changes the threading model, which may surface new timing issues. |
| **Mitigation** | 1. Port all existing BT test cases from the ObjC implementation. 2. Add exhaustive tests: pairing failure recovery, mid-transfer disconnect, rapid reconnect, 3-device gossip, large payload (100KB+). 3. Implement retry logic with exponential backoff for failed Multipeer sends. 4. The conflict resolver (LWW + field merge) handles duplicates gracefully — worst case is a redundant sync, not data loss. 5. Run soak tests: 2-hour continuous sync between 3 devices. |
| **Owner** | Phase 2, Task 2.6 |
| **Status** | Open |

### Risk 9: OCR Misreads Leading to Data Entry Errors

| Attribute | Value |
|-----------|-------|
| **Likelihood** | High |
| **Impact** | Medium (incorrect PO numbers, quantities, or supplier names entered into system) |
| **Description** | OCR accuracy varies with document quality, lighting, handwriting legibility, and print quality. Field conditions (construction sites, warehouses) produce suboptimal scan conditions. A misread quantity of "42" as "47" could cause inventory discrepancies. |
| **Mitigation** | 1. All OCR-extracted fields require user confirmation — never auto-submit. 2. Confidence scoring with color-coded indicators (green ≥ 0.90, yellow 0.70–0.89, red < 0.70). 3. Low-confidence fields not auto-filled — shown as suggestions only. 4. Real-time scan quality feedback before processing. 5. "Rescan" prompt when overall confidence < 0.50. |
| **Owner** | Phase 12+ |
| **Status** | Open |

### Risk 10: Poor Lighting Degrades Camera Part Matching

| Attribute | Value |
|-----------|-------|
| **Likelihood** | High |
| **Impact** | Medium (inaccurate or no matches for parts photographed in dark conditions) |
| **Description** | Warehouses and construction sites often have poor lighting. Flash/torch helps but can create glare. Feature extraction quality degrades significantly in low light, reducing match accuracy below useful thresholds. |
| **Mitigation** | 1. Auto-enable flash/torch when ambient light is low. 2. Image pre-processing: contrast enhancement, noise reduction before feature extraction. 3. UI guidance: "Move to better lighting" prompt when image quality score is low. 4. Allow manual search as fallback — camera matching is supplementary, not required. |
| **Owner** | Phase 12+ |
| **Status** | Open |

### Risk 11: QR Code Damage in Field Environments

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Low (user falls back to manual entry) |
| **Description** | QR labels on parts, bins, and tools get damaged in construction/warehouse environments — dirt, scratches, chemical exposure, UV fading. Standard QR has error correction up to ~30% damage (Level H), but beyond that, codes become unreadable. |
| **Mitigation** | 1. Generate QR codes at error correction level H (30% recovery). 2. Document minimum print size (15mm × 15mm). 3. Recommend matte label stock for durability. 4. Fallback: non-WiredPart codes searched against parts catalog. 5. "Couldn't read QR" → manual entry always available. |
| **Owner** | Phase 12+ |
| **Status** | Open |

### Risk 12: Predictive Text Hallucinations

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | High (fabricated entity names or incorrect data suggested to users) |
| **Description** | LLM-based predictions may generate plausible but incorrect entity names (suppliers, parts, jobs) that don't exist in the database. Users trusting ghost text suggestions could enter bad data. |
| **Mitigation** | 1. Entity-reference fields always use database lookup (not LLM) as primary suggestion source. 2. LLM only used for free-text fields (notes, descriptions, messages). 3. Ghost text clearly styled as suggestion (dimmed, distinct from user input). 4. Entity validation on form submit — flag any unrecognized entities. 5. Test suite: 100 completions verified for zero fabricated entity names. |
| **Owner** | Phase 12+ |
| **Status** | Open |

### Risk 13: Bluetooth Sync Overload from Image Data

| Attribute | Value |
|-----------|-------|
| **Likelihood** | Medium |
| **Impact** | Medium (sync sessions take too long, record sync blocked by image transfers) |
| **Description** | Adding scanned document images and part reference photos to sync payload can overwhelm Bluetooth bandwidth. A single day with 10 document scans + 5 part photos = ~15MB of binary data, which takes ~18 minutes over BT. If not managed, this blocks critical record sync. |
| **Mitigation** | 1. Priority queue: records always sync before images. 2. Image sync is never blocking — runs in background after records complete. 3. BT image sync is user-initiated ("Sync Images Now") not automatic. 4. LAN sync recommended for bulk image transfer (100× faster). 5. Progress indicator shows image sync status separately from record sync. |
| **Owner** | Phase 12+ |
| **Status** | Open |

---

## Risk Summary Heat Map

```
Impact ↑
  High  │ [R1] [R2]         [R6]     [R12]
        │
  Med   │      [R3] [R4]    [R7] [R8] [R9] [R10] [R13]
        │
  Low   │           [R5]    [R11]
        │
        └──────────────────────────────────→
          Low    Medium    High
                Likelihood
```

**Top priority risks (High impact):** R1 (schema drift), R2 (sync protocol), R6 (WAL conflict), R12 (text hallucinations)
**Medium priority:** R3 (WebView auth), R4 (NIO vs axum), R7 (Windows), R8 (BT edge cases), R9 (OCR misreads), R10 (poor lighting), R13 (BT image overload)
**Low priority:** R5 (Foundation Models timing), R11 (QR damage)
