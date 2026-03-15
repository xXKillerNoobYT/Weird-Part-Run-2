# Test Matrix

> Complete test coverage plan for the native SwiftUI migration.

---

## Summary

| Category | Core (Swift) | macOS | iOS | Windows |
|----------|:----------:|:-----:|:---:|:-------:|
| Unit tests | 250+ | — | — | — |
| Integration tests | 30+ | — | — | — |
| UI tests | — | 120+ | 120+ | TBD |
| **Total target** | **280+** | **120+** | **120+** | **TBD** |

---

## Test Matrix by Module

| Module | Unit Tests (Core) | Integration | macOS UI | iOS UI | Phase |
|--------|:-----------------:|:-----------:|:--------:|:------:|:-----:|
| **Database/Migrations** | `DatabaseTests.swift` — verify all 17 migrations apply, table existence, index existence, schema comparison with TS | — | — | — | 1 |
| **Models** | `ModelTests.swift` — Codable round-trip for every struct, insert+fetch equality, CodingKeys match DB columns | — | — | — | 1 |
| **BaseRepository** | `BaseRepositoryTests.swift` — generic CRUD, pagination, filtering, soft-delete | — | — | — | 1 |
| **ChangeTracker** | `ChangeTrackerTests.swift` — INSERT/UPDATE/DELETE tracking, changed_fields JSON, vector clock ops, pruning | — | — | — | 1 |
| **Auth** | `AuthServiceTests.swift` — seed admin, PIN auth, wrong PIN rejection, permissions, hat levels | — | Login flow, PIN pad | Login flow, PIN pad | 1/3 |
| **Settings** | `SettingsServiceTests.swift` — get/set, theme, company profile | — | All settings pages persist | Same | 1/4 |
| **ConflictResolver** | `ConflictResolverTests.swift` — LWW same-field, field-level merge, DELETE vs UPDATE, timestamp tie-break | Two-DB conflict test | — | — | 2 |
| **Crypto** | `CryptoTests.swift` — keygen, sign, verify, expired cert, invalid sig | — | — | — | 2 |
| **LanSyncServer** | `LanSyncServerTests.swift` — push/pull/status endpoints, JSON format | HTTP loopback push+pull | — | — | 2 |
| **PeerDiscovery** | `PeerDiscoveryTests.swift` — advertise/browse on loopback | Two-instance discovery | — | — | 2 |
| **MultipeerManager** | — | Two-simulator MPC test | — | — | 2 |
| **SyncEngine** | `SyncEngineTests.swift` — mock server, push-pull cycle, retry backoff, periodic timer | Full initial sync | Sync status view | Sync status view | 2 |
| **SyncProtocol** | `SyncProtocolParityTests.swift` — shared JSON fixtures, TS↔Swift round-trip | — | — | — | 2 |
| **Dashboard** | `DashboardServiceTests.swift` — summary, activity, alerts | — | Live data, real-time updates | Same | 4 |
| **Parts** | `PartsServiceTests.swift` — CRUD, hierarchy queries, search, companion rules, stock levels | — | Catalog browse, category tree, supplier CRUD | Same | 5 |
| **Warehouse** | `WarehouseServiceTests.swift` — bin locations, inventory, audit | — | Movement wizard, QR scan, receiving | Same | 6 |
| **Jobs** | `JobServiceTests.swift` — CRUD, status transitions, assignment | — | Clock in/out + GPS, questionnaire | Same | 7 |
| **Labor** | `LaborServiceTests.swift` — clock in/out, overtime, totals | — | Clock flow UI | Same | 7 |
| **Orders** | `OrderServiceTests.swift` — JPO→PO lifecycle, line items, approvals | — | Unified order form, PO detail | Same | 8 |
| **People** | `PeopleServiceTests.swift` — employee CRUD, certs, wages, skills | — | Employee list, customer detail | Same | 9 |
| **Contacts** | `ContactsServiceTests.swift` — entity contacts, directory search | — | Contact directory | Same | 9 |
| **Scheduling** | `SchedulingServiceTests.swift` — dispatch, templates, time-off | — | Calendar view, dispatch | Same | 10 |
| **Fleet** | `FleetServiceTests.swift` — vehicle CRUD, assignments, fuel | — | Vehicle list, fuel entry | Same | 11 |
| **Tools** | `ToolServiceTests.swift` — registry, kits, checkout/return | — | Tool registry, kit verify | Same | 11 |
| **Chat** | `ChatServiceTests.swift` — channels, messages, Q&A threads | — | Chat inbox, DM view | Same | 11 |
| **Notebooks** | `NotebookServiceTests.swift` — templates, sections, entries | — | Notebook detail, entry editor | Same | 11 |
| **Reports** | `ReportServiceTests.swift` — aggregation, period locking | — | Report builder, export | Same | 11 |
| **Office** | `OfficeServiceTests.swift` — PO mgmt, approvals, bundles | — | PO management, approval flow | Same | 11 |
| **AI (Foundation Models)** | `FoundationModelsTests.swift` — availability, completion, enhance | Real-device only | AI text field, enhance popover | Same | 12 |
| **AI (llama.cpp)** | `LlamaCppTests.swift` — model load, inference, fallback | — | Settings AI toggle | Same | 12 |
| **OCR Processor** | `OCRProcessorTests.swift` — field extraction, pattern matching, confidence scoring, supplier/part matching | — | Document scan flow, field pre-fill, confidence indicators | Same | 12+ |
| **QR Codec** | `QRCodecTests.swift` — encode/decode all entity types, V1 backward compat, invalid payload handling | — | QR scan → auto-fill flow, universal scan action | Same | 12+ |
| **Image Matcher** | `ImageMatcherTests.swift` — feature index build, cosine similarity, top-K ranking, empty index handling | — | Camera match view, results display, reference photo save | Same | 12+ |
| **Text Predictor** | `TextPredictorTests.swift` — entity lookup, phrase history, template expansion, LLM generation, privacy (no cross-user leak) | — | Ghost text in AITextField, autofill banner, settings toggle | Same | 12+ |
| **Binary Sync** | `BinarySyncTests.swift` — chunked transfer, resume after disconnect, hash dedup, priority ordering | Two-device binary transfer test | Sync status with image progress | Same | 12+ |
| **Navigation** | `NavigationTests.swift` — all routes resolve, no dead links | — | Full navigation stress (1000 transitions) | Same | 3+ |
| **Offline** | — | — | All CRUD works offline | Same | 3+ |
| **Performance** | — | — | Cold start <3s, RSS <200MB | Cold start <2s, RSS <100MB | 3+ |

---

## Test Types Explained

### Unit Tests (Core Package)
- Run via `swift test` — no simulator, no device
- In-memory GRDB databases — fast, isolated
- Target: <5 seconds total runtime
- Location: `core/Tests/WiredPartCoreTests/`

### Integration Tests
- Require two processes or real network
- Sync tests use loopback (127.0.0.1)
- Multipeer tests require two simulators
- Location: `core/Tests/WiredPartCoreTests/Integration/`

### UI Tests (macOS)
- XCUITest framework
- Target: macOS 14.0+ simulator or device
- Test navigation, data entry, persistence, real-time updates
- Location: `mac/WiredPartMacTests/`

### UI Tests (iOS)
- XCUITest framework
- Target: iPhone 16 simulator (iOS 18+)
- Test touch targets (44x44pt minimum), landscape/portrait, tab bar
- Location: `ios/WiredPartIOSTests/`

---

## Bluetooth Sync Test Cases

| Test Case | Description | Pass Criteria |
|-----------|-------------|---------------|
| BT-01: Peer Discovery | Two devices with same company_id | Both appear in each other's peer list within 10s |
| BT-02: Peer Filtering | Device A (company X) and Device B (company Y) | Neither discovers the other |
| BT-03: Data Send | Device A sends 1KB change payload to Device B | Device B receives identical payload |
| BT-04: Large Payload | Device A sends 100KB (bulk sync) to Device B | Data arrives complete, no corruption |
| BT-05: Conflict via BT | Both devices edit same record offline, then BT sync | LWW applies correctly, conflict logged |
| BT-06: Disconnect/Reconnect | Devices go out of range, return | Session re-establishes, missed changes sync |
| BT-07: Multi-Peer | 3 devices in range, all same company | All 3 discover each other, gossip propagates changes |

---

## AI Behavior Test Cases

| Test Case | Input | Expected | Tolerance |
|-----------|-------|----------|-----------|
| AI-01: Autocomplete | `"The delivery for job 1234 was del"` | Natural continuation, >=10 chars | Grammatically correct, no repetition |
| AI-02: Proofread | `"recived parts form supplyer, wil inspect tomorow"` | Spelling corrected, meaning preserved | All 5 misspellings fixed |
| AI-03: Pre-fill | Context: job + crew + date | Mentions all 3 context items | All 3 present in output |
| AI-04: Enhance (professional) | `"hey mike can u grab the stuff from the warehouse thx"` | Professional tone, complete sentences | No slang, proper grammar |
| AI-05: Unavailable graceful | Run on macOS <26 without llama.cpp | Plain text field, no AI UI | Zero AI-related UI elements visible |
| AI-06: Fallback chain | Foundation Models unavailable, llama.cpp available | llama.cpp activates automatically | Completion returned within 10s |

---

## OCR Accuracy Test Cases

| Test Case | Input | Expected | Pass Criteria |
|-----------|-------|----------|---------------|
| OCR-01: Printed PO | Scanned typed purchase order | PO number, dates, quantities extracted | ≥ 95% character accuracy |
| OCR-02: Handwritten qty | Photo of handwritten quantity "42" | Recognized as integer 42 | ≥ 85% accuracy across 30 samples |
| OCR-03: Supplier match | Scanned doc with "Westinghouse Electric" | Matched to known supplier | ≥ 85% correct match rate |
| OCR-04: Date formats | "03/15/2026", "March 15, 2026", "2026-03-15" | All parsed to same date | All 3 formats recognized |
| OCR-05: Part code | "ELB-90-2IN-WHT" in scanned text | Matched to catalog part | ≥ 80% correct extraction |
| OCR-06: Poor quality | Faded/creased document photo | Graceful degradation, confidence < 0.5 flagged | No crash; user prompted to rescan |
| OCR-07: Signature detect | Delivery sheet with signature | `signaturePresent = true` | ≥ 90% detection rate |
| OCR-08: Processing time | Single page scan | Results returned | < 3s on iPhone 15+, < 5s on Mac M1+ |

---

## QR Recognition Test Cases

| Test Case | Input | Expected | Pass Criteria |
|-----------|-------|----------|---------------|
| QR-01: Part QR | V2 QR with type="part" | Part entity resolved, form auto-filled | ≥ 99% recognition on clean codes |
| QR-02: Job QR | V2 QR with type="job" | Job entity resolved | Same |
| QR-03: V1 compat | V1 QR (no type field) | Treated as type="part" | 100% backward compat |
| QR-04: Non-WP QR | Random URL QR code | Raw text displayed, catalog search offered | No crash, graceful fallback |
| QR-05: Damaged QR | QR with 15% obscured | Still recognized | ≥ 80% at 15% damage |
| QR-06: Low light | QR scan in dim room with torch | Recognized | ≥ 90% accuracy |
| QR-07: Distance | QR scanned at 30cm | Recognized on iPhone | Readable at 30cm+ |
| QR-08: Multi-QR | Two QR codes in frame | Closest/largest selected | Correct selection |
| QR-09: Scan latency | Time from detection to field fill | < 500ms | Measured on iPhone 15 |
| QR-10: Barcode 128 | Code 128 barcode | Value extracted | ≥ 95% accuracy |

---

## Camera Part Matching Test Cases

| Test Case | Input | Expected | Pass Criteria |
|-----------|-------|----------|---------------|
| IMG-01: Exact match | Photo of known part (white background) | Correct part is #1 result | ≥ 60% top-1 accuracy |
| IMG-02: Top-3 | Photo of known part (field conditions) | Correct part in top 3 | ≥ 80% top-3 accuracy |
| IMG-03: Top-5 | Same photo set | Correct part in top 5 | ≥ 90% top-5 accuracy |
| IMG-04: Unknown part | Photo of part NOT in catalog | Low confidence, no false high match | < 10% false positive at ≥ 0.7 threshold |
| IMG-05: Similar parts | Photo of 2" elbow (3 sizes in catalog) | All sizes shown in results | All similar parts in top 5 |
| IMG-06: Poor lighting | Dark/shadowed photo | Results returned with lower confidence | No crash; confidence reflects quality |
| IMG-07: Processing time | Capture to results | Results displayed | < 2s iPhone 15+, < 3s Mac M1+ |
| IMG-08: Index build | 1,000 parts with images | Index built successfully | < 60 seconds |
| IMG-09: No images | Catalog with 0 reference images | "No catalog images" message | Graceful empty state |
| IMG-10: Memory | 1,000-part index loaded | RSS overhead | < 10MB additional |

---

## Predictive Text Test Cases

| Test Case | Input | Expected | Pass Criteria |
|-----------|-------|----------|---------------|
| TXT-01: Entity suggest | Type "Westing" in supplier field | "Westinghouse Electric" suggested | ≥ 80% relevance |
| TXT-02: Phrase complete | Type "Received del" in PO notes | "Received delivery from..." completed | ≥ 70% acceptance rate |
| TXT-03: LLM ghost | Type "The crew arr" in job notes | Natural continuation appears | Grammatically correct |
| TXT-04: No hallucinate | Entity field with context | No fabricated entity names | 0% fabrication rate |
| TXT-05: Autofill PO | Open new PO with known supplier | Supplier contact, address pre-filled | ≥ 85% correct fields |
| TXT-06: Autofill daily | Open daily report (crew clocked in) | Crew names, job, hours pre-filled | ≥ 85% correct fields |
| TXT-07: Entity latency | Type character in entity field | Suggestion appears | < 10ms p95 |
| TXT-08: LLM latency | Type in free-text field | Ghost text appears | < 2s first token |
| TXT-09: Privacy | User A's text history | Not visible to User B | Zero cross-user leak |
| TXT-10: Graceful off | AI disabled in settings | All fields work as plain text | Zero AI UI elements |

---

## Binary Sync Test Cases

| Test Case | Description | Pass Criteria |
|-----------|-------------|---------------|
| BS-01: Chunked transfer | Send 1MB image over BT | Complete, hash-verified, < 90s |
| BS-02: Resume | Disconnect mid-transfer, reconnect | Transfer resumes from last chunk, < 10s resume |
| BS-03: Priority order | Queue records + images simultaneously | Records sync before images complete |
| BS-04: Dedup | Same image synced A→B, then B→C | C doesn't re-request from A (hash dedup) |
| BS-05: LAN speed | Transfer 100MB of images over LAN | ≥ 5 MB/s throughput |
| BS-06: Disk full | Receiver at storage limit | Transfer skipped, records still sync, user warned |
| BS-07: Manifest exchange | Two devices compare attachment lists | Only missing attachments requested |
| BS-08: Records unblocked | 50MB pending images | Record sync completes within 5s regardless |

---

## Phase Completion Test Gates

Each phase must pass its gate before merging to `dev`:

| Phase | Gate |
|-------|------|
| 1 | `swift build` + `swift test` — all 50+ tests pass, schema parity verified |
| 2 | Sync loopback test + conflict test + JSON fixture test — all pass |
| 3 | macOS app launches, sidebar renders, WebFallback loads React, auth flow completes |
| 4 | Dashboard + all Settings pages native, data persists, theme changes instantly |
| 5–11 | Module's service tests + UI tests pass, WebFallback retired for module |
| 12 | AI canonical prompts pass on real device, graceful degradation verified |
| 12+ | OCR: 8 test cases pass. QR: 10 test cases pass. Image match: 10 test cases pass. Predictive text: 10 test cases pass. Binary sync: 8 test cases pass. All acceptance criteria met. |
| 15 | `src/` and `src-tauri/` removed, all tests still pass, both apps ship |
