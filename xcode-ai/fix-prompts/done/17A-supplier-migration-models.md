# 17A — Supplier System: Migration + StockMovement Model

> **Chain position:** **17A** → 17B (form) → 17C–17H
> **Prerequisite:** Prompts 01–16I complete
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The Suppliers page needs improvements. Before building UI, we need:

1. **Account number column** on the `suppliers` table — most businesses have a customer account number with each supplier.
2. **StockMovement model struct** — the `stock_movements` table exists (migration 002) but has NO Swift model wrapper. This is needed for part traceability (tracking a part from supplier → shop → truck → job).
3. **Supplier performance score columns** need to be verified — they exist on the Supplier model but may need service methods.

**Key files:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` (Supplier model)
- `core/Sources/WiredPartCore/Models/Warehouse/` or `Models/Parts/` — new StockMovement struct
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` (verify stock_movements in whitelist)

## Task

### Step 1: Add migration 026 for supplier account number

In `AppDatabase+Migrations.swift`, register a new migration:

```swift
// MARK: - 026: Supplier Enhancements

extension AppDatabase {
    private static func registerMigration026SupplierEnhancements(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("026_supplier_enhancements") { db in
            // Add account number to suppliers
            try db.alter(table: "suppliers") { t in
                t.add(column: "account_number", .text)  // customer account # with this supplier
            }
        }
    }
}
```

Register it in `registerAllMigrations`:
```swift
registerMigration026SupplierEnhancements(&migrator)
```

### Step 2: Add `accountNumber` to the Supplier model

Find the `Supplier` struct in `PartsModels.swift`. Add the property and CodingKey:

```swift
public var accountNumber: String?
```

In the CodingKeys enum:
```swift
case accountNumber = "account_number"
```

Make sure the `init` method (if one exists) includes `accountNumber`.

### Step 3: Create StockMovement model

The `stock_movements` table exists (created in migration 002) with columns:
- id, part_id, qty, from_location_type, from_location_id, to_location_type, to_location_id
- supplier_id, movement_type, reason, reference_number, notes
- job_id, performed_by, verified_by, photo_path, scan_confirmed
- gps_lat, gps_lng, unit_cost_at_move, unit_sell_at_move
- deleted_at, created_at

Find where stock/movement-related models are defined. If there's a `WarehouseModels.swift` or similar file, add there. Otherwise add to `PartsModels.swift` or create a new file.

```swift
// MARK: - StockMovement

public struct StockMovement: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "stock_movements"
    public var id: Int64?
    public var partId: Int64
    public var qty: Int
    public var fromLocationType: String?
    public var fromLocationId: Int64?
    public var toLocationType: String?
    public var toLocationId: Int64?
    public var supplierId: Int64?
    public var movementType: String
    public var reason: String?
    public var referenceNumber: String?
    public var notes: String?
    public var jobId: Int64?
    public var performedBy: Int64
    public var verifiedBy: Int64?
    public var photoPath: String?
    public var scanConfirmed: Int
    public var gpsLat: Double?
    public var gpsLng: Double?
    public var unitCostAtMove: Double?
    public var unitSellAtMove: Double?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, qty, reason, notes
        case partId = "part_id"
        case fromLocationType = "from_location_type"
        case fromLocationId = "from_location_id"
        case toLocationType = "to_location_type"
        case toLocationId = "to_location_id"
        case supplierId = "supplier_id"
        case movementType = "movement_type"
        case referenceNumber = "reference_number"
        case jobId = "job_id"
        case performedBy = "performed_by"
        case verifiedBy = "verified_by"
        case photoPath = "photo_path"
        case scanConfirmed = "scan_confirmed"
        case gpsLat = "gps_lat"
        case gpsLng = "gps_lng"
        case unitCostAtMove = "unit_cost_at_move"
        case unitSellAtMove = "unit_sell_at_move"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    /// Human-readable description of the movement
    public var movementDescription: String {
        let from = fromLocationType?.capitalized ?? "Unknown"
        let to = toLocationType?.capitalized ?? "Unknown"
        return "\(from) → \(to)"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 4: Add traceability service methods to PartsService

In `core/Sources/WiredPartCore/Services/PartsService.swift`, add a new section:

```swift
// =========================================================================
// MARK: - 10. Part Traceability
// =========================================================================

/// A single step in a part's journey from supplier to job.
public struct TraceStep: Sendable {
    public let movementId: Int64
    public let date: String
    public let movementType: String     // "receipt", "transfer", "consumption", "return"
    public let fromLocation: String     // e.g. "Supplier: ABC Supply"
    public let toLocation: String       // e.g. "Warehouse: Main"
    public let qty: Int
    public let unitCost: Double?
    public let performedByName: String?
    public let referenceNumber: String? // PO#, etc.
    public let notes: String?
}

/// Trace all movements for a specific part, ordered chronologically.
/// Shows the full journey: Supplier → Warehouse → Staging → Truck → Job
public func tracePartMovements(partId: Int64) throws -> [TraceStep] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT sm.*, u.display_name AS performer_name
            FROM stock_movements sm
            LEFT JOIN users u ON u.id = sm.performed_by
            WHERE sm.part_id = ? AND sm.deleted_at IS NULL
            ORDER BY sm.created_at ASC
            """, arguments: [partId])

        return rows.map { row in
            let fromType: String? = row["from_location_type"]
            let toType: String? = row["to_location_type"]
            let fromId: Int64? = row["from_location_id"]
            let toId: Int64? = row["to_location_id"]

            return TraceStep(
                movementId: row["id"],
                date: row["created_at"] ?? "",
                movementType: row["movement_type"] ?? "transfer",
                fromLocation: describeLocation(type: fromType, id: fromId),
                toLocation: describeLocation(type: toType, id: toId),
                qty: row["qty"],
                unitCost: row["unit_cost_at_move"],
                performedByName: row["performer_name"],
                referenceNumber: row["reference_number"],
                notes: row["notes"]
            )
        }
    }
}

/// Trace movements for a part filtered by supplier — shows everything from a specific supplier.
public func tracePartFromSupplier(partId: Int64, supplierId: Int64) throws -> [TraceStep] {
    let allSteps = try tracePartMovements(partId: partId)
    // Find the chain starting from this supplier
    // A part enters from a supplier via "receipt" type, then transfers through locations
    var inChain = false
    var chain: [TraceStep] = []
    for step in allSteps {
        if step.fromLocation.contains("Supplier") && step.movementType == "receipt" {
            // Check if this receipt is from our target supplier
            // Simple heuristic: if the chain was from another supplier, cut it
            inChain = true
            chain = [step]
        } else if inChain {
            chain.append(step)
        }
    }
    return chain
}

/// Get the current location of a part's stock — where is it right now?
public func getPartCurrentLocations(partId: Int64) throws -> [(locationType: String, locationId: Int64, qty: Int)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT location_type, location_id, qty
            FROM stock
            WHERE part_id = ? AND qty > 0 AND deleted_at IS NULL
            ORDER BY qty DESC
            """, arguments: [partId])

        return rows.map { row in
            (locationType: row["location_type"] ?? "unknown",
             locationId: row["location_id"] ?? 0,
             qty: row["qty"] ?? 0)
        }
    }
}

/// Helper: describe a location as a human-readable string
private func describeLocation(type: String?, id: Int64?) -> String {
    guard let type = type else { return "Unknown" }
    switch type.lowercased() {
    case "supplier": return "Supplier"
    case "warehouse": return "Warehouse"
    case "staging": return "Staging Area"
    case "job": return "Job Site"
    case "truck", "vehicle": return "Truck"
    default: return type.capitalized
    }
}
```

### Step 5: Verify ConflictResolver whitelist

In `ConflictResolver.swift`, check that `stock_movements` is in the `allowedTables` set. If not, add it. It should already be there from earlier migrations.

## Success Criteria

- [ ] Migration 026 adds `account_number` column to suppliers table
- [ ] Supplier model has `accountNumber` property with CodingKey
- [ ] StockMovement model struct created with all 20+ columns mapped
- [ ] `tracePartMovements` returns chronological journey for a part
- [ ] `tracePartFromSupplier` filters trace to a specific supplier chain
- [ ] `getPartCurrentLocations` shows where stock lives right now
- [ ] stock_movements in ConflictResolver whitelist
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17A Results (YYYY-MM-DD)
- Migration 026: account_number column on suppliers
- StockMovement model struct (20+ columns)
- Service: tracePartMovements, tracePartFromSupplier, getPartCurrentLocations
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17B.**
