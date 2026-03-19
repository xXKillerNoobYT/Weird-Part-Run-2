# Fix Prompt 10: Service Layer Bugs

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

Some data doesn't load correctly, counts are wrong, or operations silently fail because of bugs in the service layer (the Swift code that talks to the database).

---

## Files To Fix

### 1. SchedulingService.swift — endDate Parameter Ignored

**File:** `core/Sources/WiredPartCore/Services/SchedulingService.swift`

Find `createTimeOffRequest`. The `endDate` parameter is accepted but never used in the SQL INSERT. A 3-day vacation request gets saved as a 1-day request.

Fix: Include `endDate` in the INSERT statement columns and values.

### 2. PeopleService.swift — Missing Columns

**File:** `core/Sources/WiredPartCore/Services/PeopleService.swift`

Some queries reference `users.status` and `users.role` columns. Check the migration files (`core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`) to verify these columns exist. If they don't:
- Either add them via a new migration
- Or remove the references and use a different approach

### 3. OrdersService.swift — Status History Table Mismatch

**File:** `core/Sources/WiredPartCore/Services/OrdersService.swift`

The service writes to `"status_history"` but the model maps to `"order_status_history"`. One of these is wrong. Check the migration to see which table actually exists, then make the service match.

### 4. ToolsService.swift — listKits Returns Tools Instead of Kits

**File:** `core/Sources/WiredPartCore/Services/ToolsService.swift`

`listKits()` is a workaround that returns tools, not actual kits. Check if the `tool_kits` table exists in migrations. If it does, query it properly. If it doesn't, add a migration for it.

### 5. ToolsService.swift — getToolsStats Overcounts

**File:** `core/Sources/WiredPartCore/Services/ToolsService.swift`

`getToolsStats()` counts ALL checkout records for `checkedOut`, not just active ones. Fix:

```swift
// CURRENT (wrong — counts returned items too)
let checkedOut = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tool_checkouts")

// FIX (only count active checkouts)
let checkedOut = try Int.fetchOne(db, sql: """
    SELECT COUNT(*) FROM tool_checkouts
    WHERE returned_at IS NULL AND deleted_at IS NULL
""")
```

### 6. ConflictResolver.swift — Inconsistent Timestamp Format

**File:** `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`

`currentTimestamp()` uses `DateFormatter` with `"yyyy-MM-dd HH:mm:ss"` format, while the rest of the codebase uses `ISO8601DateFormatter`. Fix:

```swift
private func currentTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}
```

### 7. FleetService.swift — Force Unwraps

**File:** `core/Sources/WiredPartCore/Services/FleetService.swift`

Multiple locations use `StatementArguments(args as [Any])!`. If `args` contains an unsupported type, this crashes. Replace with safe construction:

```swift
// CURRENT (crash risk)
let arguments = StatementArguments(args as [Any])!

// FIX
guard let arguments = StatementArguments(args) else {
    throw FleetServiceError.invalidArguments
}
```

### 8. IOSOCRScanner.swift — MainActor.assumeIsolated Crash Risk

**File:** `Scanning/IOSOCRScanner.swift`

`nonisolated var isAvailable` wraps `MainActor.assumeIsolated { ... }`. This crashes if called from a background thread. Fix by making the property `@MainActor`:

```swift
// CURRENT (crash if called from background)
nonisolated var isAvailable: Bool {
    MainActor.assumeIsolated { ... }
}

// FIX
@MainActor var isAvailable: Bool {
    // direct access, no assumption needed
}
```

### 9. FoundationModelsService.swift — Unnecessary Actor Overhead

**File:** `core/Sources/WiredPartCore/AI/FoundationModelsService.swift`

`checkAvailability()` is synchronous but on an actor, forcing callers to `await`. If there's no async work inside, consider making it `nonisolated` or marking the whole type as `@MainActor` since it's UI-related.

### 10. Duplicate Utility Functions

These functions are copy-pasted across 12+ files. Consolidate them into a single `Formatters.swift` utility:
- `safeCount()` — helper for optional arrays
- `formatTime()` — time formatting
- `formatDate()` — date formatting
- `formatCurrency()` — currency formatting

Create `Shared/Formatters.swift`:
```swift
import Foundation

enum Formatters {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func formatCurrency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
```

Then replace local versions in each file with calls to `Formatters.formatDate(...)` etc.

---

## Testing Checklist

1. Create a multi-day time-off request → both start and end dates should be saved
2. Tools dashboard → "Checked Out" count should only reflect items NOT yet returned
3. Open any fleet page → no crashes from force unwraps
4. Sync conflict resolution → timestamps use consistent ISO8601 format
5. OCR scanner → calling `isAvailable` from any context doesn't crash

---

## All 10 Prompts Complete

You've finished the full audit fix chain. Review the changes, build the project, and test the flows from a user's perspective:

1. Can I create, edit, and delete items everywhere I'd expect to?
2. Do popups open AND close properly?
3. Do I see clear error messages when things go wrong?
4. Does the app never show "Phase X" or developer placeholder text?
5. Does the app never get stuck on an infinite spinner?
