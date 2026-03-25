# 60K — Stock Location Human-Readable Names

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The PartDetailSheet in PartsCatalogPage.swift displays stock entries with hardcoded `"Warehouse #\(entry.warehouseId)"` instead of the actual warehouse location name. The `warehouse_locations` table (migration 020) has a `name` column. Look up the name from the service and display it.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — find the `PartDetailSheet` section and the stock display around line 1428
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — find warehouse location lookup methods

## Task

### Step 1: Add a warehouse name lookup to WarehouseService

In `core/Sources/WiredPartCore/Services/WarehouseService.swift`, add this method:

```swift
/// Look up a warehouse location name by ID. Returns nil if not found.
public func getWarehouseLocationName(id: Int64) throws -> String? {
    try db.writer.read { dbConn in
        try String.fetchOne(dbConn, sql: """
            SELECT name FROM warehouse_locations WHERE id = ? AND deleted_at IS NULL
            """, arguments: [id])
    }
}
```

### Step 2: Add a batch lookup method (for efficiency)

Also in WarehouseService, add:

```swift
/// Look up multiple warehouse location names by IDs. Returns a dictionary of id → name.
public func getWarehouseLocationNames(ids: [Int64]) throws -> [Int64: String] {
    guard !ids.isEmpty else { return [:] }
    return try db.writer.read { dbConn in
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT id, name FROM warehouse_locations
            WHERE id IN (\(placeholders)) AND deleted_at IS NULL
            """, arguments: StatementArguments(ids.map { DatabaseValue($0) }))
        var result: [Int64: String] = [:]
        for row in rows {
            if let id = row["id"] as Int64?, let name = row["name"] as String? {
                result[id] = name
            }
        }
        return result
    }
}
```

### Step 3: Update PartDetailSheet stock display

In `PartsCatalogPage.swift`, find the `PartDetailSheet` struct. Add a state variable:

```swift
@State private var warehouseNames: [Int64: String] = [:]
```

In the `.onAppear` or `.task` block of PartDetailSheet, after loading `stockEntries`, add:

```swift
// Look up warehouse names
let ids = stockEntries.map(\.warehouseId)
if let service = appCore.warehouseService, !ids.isEmpty {
    warehouseNames = (try? service.getWarehouseLocationNames(ids: ids)) ?? [:]
}
```

Then replace this line (around line 1428):

```swift
Text("Warehouse #\(entry.warehouseId)")
```

With:

```swift
Text(warehouseNames[entry.warehouseId] ?? "Location #\(entry.warehouseId)")
```

This shows the actual warehouse name (e.g., "Main Shop", "Storage Yard") and falls back to "Location #X" if no name is found.

## Files to Modify

- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — add `getWarehouseLocationName(id:)` and `getWarehouseLocationNames(ids:)`
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — update PartDetailSheet to load and display warehouse names

## Success Criteria

- [ ] `getWarehouseLocationNames(ids:)` method exists on WarehouseService
- [ ] PartDetailSheet loads warehouse names in its `.task` or `.onAppear`
- [ ] Stock entries display actual warehouse location name (e.g., "Main Shop")
- [ ] Fallback text is "Location #X" (not "Warehouse #X") when name lookup fails
- [ ] No force unwraps — uses optional chaining and nil coalescing
- [ ] Builds without errors
