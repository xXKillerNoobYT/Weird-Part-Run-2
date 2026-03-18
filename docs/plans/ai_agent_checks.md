# AI Agent Cross-Platform Validation Checks

> Defines the automated checks that validate cross-platform parity between macOS, iOS, and Windows builds.

---

## 1. Static Analysis Checks

### 1.1 No External Network Calls

**Check:** Scan all Swift source for `URLSession`, `URLRequest`, `NWConnection` — every instance must target either `localhost`, `0.0.0.0`, or a local mDNS-resolved address. No hardcoded external URLs.

**Tool:** Custom SwiftLint rule or grep-based CI check.

**Pass criteria:** Zero external URL references in production code. Only allowed: `_wiredpart._tcp` Bonjour service, `localhost`, `127.0.0.1`, `0.0.0.0`, and mDNS-resolved `.local` addresses.

**Exceptions:** None. The app is local-only. Bluetooth (Multipeer) doesn't use URLs.

### 1.2 Core Package Has No UI Imports

**Check:** Scan `core/Sources/` for `import SwiftUI`, `import UIKit`, `import AppKit`, `import WinUI`.

**Pass criteria:** Zero UI framework imports in Core. Only allowed: Foundation, GRDB, CryptoKit, Network, MultipeerConnectivity, NIO.

### 1.3 All DB Writes Track Changes

**Check:** Scan for `.insert(`, `.update(`, `.delete(` calls in Core services. Each must be inside a `db.write { }` block that also calls `ChangeTracker.track()`.

**Pass criteria:** No untracked writes. Automated test: insert a record, verify `_change_log` entry exists.

### 1.4 Platform-Gated Code Uses Correct Guards

**Check:** All Multipeer code behind `#if canImport(MultipeerConnectivity)`. All Foundation Models code behind `#if canImport(FoundationModels)` + `@available` check. All Windows code behind `#if os(Windows)`.

**Pass criteria:** Core package compiles on macOS, iOS, and Linux (and eventually Windows) with `swift build`.

---

## 2. Schema Parity Check

### 2.1 GRDB vs TypeScript Migration Comparison

**Check:** Run both migration paths on fresh databases:
1. TypeScript path: `src/local/migrations/` → SQLite via tauri-plugin-sql
2. Swift path: `core/Sources/.../Migrations/` → SQLite via GRDB

Compare schemas using `sqlite3 .schema` on both databases.

**Tool:** `SchemaComparisonTool.swift` (custom test utility)

```swift
func testSchemaParity() throws {
    let tsDB = try openTSSQLiteDatabase()  // pre-built from TS migrations
    let swiftDB = try AppDatabase.openInMemoryDatabase()
    try swiftDB.runMigrations()

    let tsTables = try tsDB.tables()
    let swiftTables = try swiftDB.tables()
    XCTAssertEqual(tsTables.sorted(), swiftTables.sorted())

    for table in tsTables {
        let tsColumns = try tsDB.columns(of: table)
        let swiftColumns = try swiftDB.columns(of: table)
        XCTAssertEqual(tsColumns, swiftColumns, "Column mismatch in table: \(table)")
    }
}
```

**Pass criteria:** Every table, column name, column type, NOT NULL constraint, and DEFAULT value matches exactly between TypeScript and Swift migration outputs.

---

## 3. Sync Protocol Parity Check

### 3.1 JSON Wire Format Compatibility

**Check:** Define canonical JSON fixtures for every sync message type:

**Push request fixture:**
```json
{
  "device_id": "test-device-001",
  "company_id": "test-company",
  "changes": [
    {
      "id": 1,
      "device_id": "test-device-001",
      "table_name": "users",
      "record_id": "42",
      "operation": "UPDATE",
      "changed_fields": "{\"display_name\":\"New Name\"}",
      "old_values": "{\"display_name\":\"Old Name\"}",
      "record_data": "{\"id\":42,\"display_name\":\"New Name\",\"email\":\"test@test.com\"}",
      "timestamp": "2026-03-14T12:00:00.000Z"
    }
  ]
}
```

**Tests:**
1. Swift `LanSyncServer` accepts this exact JSON → returns 200
2. Swift `SyncEngine` sends JSON in this exact format → TypeScript peer-manager accepts it
3. Round-trip: Swift → JSON → TypeScript → JSON → Swift → verify data integrity

**Pass criteria:** All shared JSON fixtures parse correctly on both platforms with zero data loss.

### 3.2 Conflict Resolution Determinism

**Check:** Given identical conflict scenarios, both TypeScript and Swift conflict resolvers produce the same winner.

**Fixtures:**
1. Same field, different timestamps → later wins
2. Same field, same timestamp → device ID tiebreaker (alphabetically first wins)
3. Different fields on same record → both apply (field-level merge)
4. DELETE vs UPDATE → DELETE wins

**Pass criteria:** All 4 scenarios produce identical results on both platforms.

---

## 4. UI Flow Parity Check

### 4.1 Navigation Completeness

**Check:** Every route in the React router (`App.tsx` — 100+ routes) has either:
- A native SwiftUI view registered in `NavigationRouter`, OR
- A WebFallback route that loads the React page

**Tool:** `NavigationCompletenessTest.swift`

```swift
func testAllRoutesRegistered() {
    let allRoutes = AppDestination.allCases
    for route in allRoutes {
        let view = NavigationRouter().view(for: route)
        XCTAssertNotNil(view, "Missing view for route: \(route)")
    }
}
```

**Pass criteria:** 100% of routes resolve to either a native view or WebFallback. Zero dead routes.

### 4.2 Data Input/Output Parity

For each ported page, verify:
1. Creating a record in SwiftUI produces the same DB rows as creating via React
2. Editing a record preserves all fields
3. Deleting a record follows the same soft-delete vs hard-delete pattern
4. List views show the same records with the same sort order

**Tool:** Automated UI tests that perform CRUD and verify DB state.

**Pass criteria:** Given the same DB state, SwiftUI and React views produce identical SQL queries (verified by GRDB logging).

---

## 5. AI Behavior Checks

### 5.1 Canonical Prompt Tests

Three canonical prompts tested on every platform with AI enabled:

| # | Type | Input | Expected Output Pattern |
|---|------|-------|------------------------|
| 1 | Autocomplete | `"The delivery for job 1234 was del"` | Completion continues naturally, >=10 chars, grammatically correct |
| 2 | Enhance (proofread) | `"recived parts form supplyer, wil inspect tomorow"` | All misspellings corrected, meaning preserved, similar length |
| 3 | Pre-fill | Context: `{jobName: "Smith Renovation", crewLead: "Mike", date: "2026-03-15"}` | Output mentions job name, crew lead, and date |

**Pass criteria:**
- Autocomplete: output is >=10 characters, no repetition, grammatically valid
- Proofread: Levenshtein distance from original >5 (meaningful corrections made), semantic similarity >0.8
- Pre-fill: all 3 context fields appear in output

### 5.2 AI Graceful Degradation

**Check:** On devices without AI (older OS, Windows without Copilot):
1. `checkAvailability()` returns non-`.available` status
2. `AITextField` renders as a plain `TextEditor` — no sparkles button, no ghost text
3. No error popups or crashes
4. All text fields remain fully functional for manual entry

**Pass criteria:** App is fully usable with AI completely disabled. Zero UI elements reference AI when unavailable.

### 5.3 AI Fallback Chain

**Check:** Test the fallback sequence:
1. Foundation Models available → use it (macOS/iOS 26+)
2. Foundation Models unavailable + llama.cpp model downloaded → use llama.cpp
3. Neither available → AI features disabled, plain text fields

**Pass criteria:** Each fallback level activates correctly. User toggle in Settings overrides auto-detection.

---

## 6. Performance Checks

### 6.1 Cold Start

| Platform | Target | Measurement |
|----------|--------|-------------|
| macOS | <3 seconds to first interactive paint | `os_signpost` from `applicationDidFinishLaunching` to first `onAppear` |
| iOS | <2 seconds to first interactive paint | Same measurement |

### 6.2 Memory Usage

| Platform | Target | Measurement |
|----------|--------|-------------|
| macOS | <200 MB RSS at idle (after loading dashboard) | Instruments Allocations |
| iOS | <100 MB RSS at idle | Instruments Allocations |

### 6.3 AI Response Latency

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Autocomplete (Foundation Models) | <2 seconds for first token | Wall clock from `generateCompletion` call to first result character |
| Enhance (Foundation Models) | <5 seconds for full result | Wall clock from `enhanceText` call to completion |
| Autocomplete (llama.cpp) | <5 seconds for first token | Same |

### 6.4 Sync Performance

| Operation | Target |
|-----------|--------|
| Push 100 changes | <2 seconds over LAN |
| Pull 1000 changes (initial sync) | <10 seconds over LAN |
| Multipeer message round-trip | <500ms |
| mDNS discovery | <5 seconds to first peer |

---

## 7. Stability Checks

### 7.1 Automated Navigation Stress Test

**Check:** XCUITest that navigates to every registered route, waits 2 seconds, then moves to the next. Runs 10 full loops (1000+ navigation events per platform).

**Pass criteria:** Zero crashes in 1000 automated navigation transitions per platform.

### 7.2 Offline Resilience

**Check:** Enable airplane mode (or disconnect network). Perform:
1. Navigate all modules
2. Create a record
3. Edit a record
4. Delete a record
5. View dashboard
6. Use AI (if llama.cpp available)

**Pass criteria:** All operations succeed offline. No error dialogs about network. Sync status shows "Offline" gracefully.

---

## Check Execution Schedule

| Check | When to Run | Automated? |
|-------|------------|------------|
| No external network calls | Every PR | Yes (CI grep) |
| Core has no UI imports | Every PR | Yes (CI grep) |
| All writes track changes | Every PR | Yes (unit test) |
| Schema parity | Phase 1 completion, then every migration change | Yes (test) |
| Sync JSON parity | Phase 2 completion, then every sync change | Yes (test) |
| Navigation completeness | Each feature phase completion | Yes (test) |
| AI canonical prompts | Phase 12 completion | Semi-auto (needs device) |
| AI graceful degradation | Phase 12 completion | Yes (test) |
| Cold start | Each phase completion | Manual (Instruments) |
| Memory usage | Each phase completion | Manual (Instruments) |
| Navigation stress | Each phase completion | Yes (XCUITest) |
| Offline resilience | Each phase completion | Yes (XCUITest) |
