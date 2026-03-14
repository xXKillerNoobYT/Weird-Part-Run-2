# Test Matrix

> Complete test coverage plan for the native SwiftUI migration.

---

## Summary

| Category | Core (Swift) | macOS | iOS | Windows |
|----------|:----------:|:-----:|:---:|:-------:|
| Unit tests | 200+ | — | — | — |
| Integration tests | 20+ | — | — | — |
| UI tests | — | 100+ | 100+ | TBD |
| **Total target** | **220+** | **100+** | **100+** | **TBD** |

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
| 15 | `src/` and `src-tauri/` removed, all tests still pass, both apps ship |
