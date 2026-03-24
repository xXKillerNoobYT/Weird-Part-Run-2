# 27B — JPO Per-Part Status Model + Smart Routing

> **Chain position:** 27A → **27B** → 27C → 27D → 27E
> **Prerequisite:** 27A complete (ActiveSheet, Create JPO)
> **Plan:** `docs/plans/ios-jpo-page.md` — Per-Part Status System + Smart Routing
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

Currently JPOs have a single status at the JPO level (pending, approved, rejected). The design requires per-LINE-ITEM statuses so each part can be independently approved, held, transferred, or rejected. Additionally, when a JPO is created, the system should automatically check stock: if the part is at the shop or on the user's truck, it auto-creates a transfer request (no approval needed). Only parts that need to be ordered from a supplier require approval.

**Files to read first:**
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — JPOLineRow struct (~line 117), createJPO/addJPOLineItem methods
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — find the JPO-related table creation
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — look for stock checking methods

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — new migration
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — update JPOLineRow, add per-line status methods, add smart routing

## Task

### Step 1: Migration — add per-line status + delivery options

Add a new migration (use the next number after the last migration, check what exists):

```swift
private static func registerMigration032JPOPerPartStatus(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("032_jpo_per_part_status") { db in
        // Add per-line status to jpo_lines
        try db.alter(table: "jpo_lines") { t in
            t.add(column: "line_status", .text).defaults(to: "pending")
            // pending, approved, on_hold, rejected, transfer,
            // in_procurement, ordered, received, backorder, staged, delivered
            t.add(column: "hold_reason", .text)
            t.add(column: "reject_reason", .text)
            t.add(column: "chat_thread_id", .integer)  // links to chat for on_hold Q&A
            t.add(column: "po_line_id", .integer)       // links to PO line item after procurement
            t.add(column: "transfer_id", .integer)       // links to stock_movement for transfers
            t.add(column: "status_updated_at", .text)
            t.add(column: "status_updated_by", .integer)
        }

        // Add delivery option to job_purchase_orders
        try db.alter(table: "job_purchase_orders") { t in
            t.add(column: "delivery_option", .text).defaults(to: "partial")
            // "partial" = deliver as parts arrive
            // "full" = wait for complete order
            t.add(column: "delivery_locked", .integer).defaults(to: 0)
            // 1 once any parts are delivered — can't change after
        }

        // Set all existing jpo_lines to "pending"
        try db.execute(sql: """
            UPDATE jpo_lines SET line_status = 'pending'
            WHERE line_status IS NULL
            """)
    }
}
```

**Register it** in `registerMigrations()` after the last migration call.

### Step 2: Update JPOLineRow struct

Add the new fields:

```swift
public struct JPOLineRow: Sendable, Identifiable {
    public let id: Int64
    public let jpoId: Int64
    public let partId: Int64?
    public let partName: String?
    public let description: String?
    public let quantity: Int
    public let unitPrice: Double?
    public let notes: String?
    public let priority: String
    public let lineStatus: String        // NEW
    public let holdReason: String?       // NEW
    public let rejectReason: String?     // NEW
    public let chatThreadId: Int64?      // NEW
    public let poLineId: Int64?          // NEW
    public let transferId: Int64?        // NEW
    public let createdAt: String?
    // ... update init accordingly
}
```

Update the `getJPODetail` SQL query to select these new columns.

### Step 3: Add JPO overall status derivation

Add a computed property or method that derives the JPO-level status from its line items:

```swift
/// Derive JPO overall status from per-line statuses.
public func deriveJPOStatus(lines: [JPOLineRow]) -> String {
    let statuses = Set(lines.map(\.lineStatus))
    if statuses.isEmpty { return "draft" }
    if statuses == ["pending"] { return "pending" }
    if statuses == ["rejected"] { return "rejected" }
    if statuses.allSatisfy({ ["delivered"].contains($0) }) { return "complete" }
    if statuses.allSatisfy({ ["ordered", "received", "backorder", "staged", "delivered", "in_procurement"].contains($0) }) { return "ordered" }
    if statuses.allSatisfy({ ["approved", "transfer", "in_procurement", "ordered", "received", "backorder", "staged", "delivered"].contains($0) }) { return "approved" }
    return "in_review"
}
```

### Step 4: Add per-line status update methods

```swift
/// Update a single JPO line item's status.
public func updateJPOLineStatus(lineId: Int64, status: String, reason: String? = nil, updatedBy: Int64? = nil) throws {
    try db.writer.write { dbConn in
        var setClauses = ["line_status = ?", "status_updated_at = datetime('now')"]
        var args: [DatabaseValueConvertible?] = [status]

        if let by = updatedBy {
            setClauses.append("status_updated_by = ?")
            args.append(by)
        }
        if status == "on_hold", let reason {
            setClauses.append("hold_reason = ?")
            args.append(reason)
        }
        if status == "rejected", let reason {
            setClauses.append("reject_reason = ?")
            args.append(reason)
        }
        args.append(lineId)

        try dbConn.execute(
            sql: "UPDATE jpo_lines SET \(setClauses.joined(separator: ", ")) WHERE id = ?",
            arguments: StatementArguments(args)
        )

        // Update parent JPO status based on all lines
        if let jpoId = try Int64.fetchOne(dbConn, sql: "SELECT jpo_id FROM jpo_lines WHERE id = ?", arguments: [lineId]) {
            let allLines = try Row.fetchAll(dbConn, sql: "SELECT line_status FROM jpo_lines WHERE jpo_id = ?", arguments: [jpoId])
            let derived = deriveJPOStatusFromRows(allLines.map { $0["line_status"] as String })
            try dbConn.execute(
                sql: "UPDATE job_purchase_orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [derived, jpoId]
            )
        }
    }
}

private func deriveJPOStatusFromRows(_ statuses: [String]) -> String {
    let unique = Set(statuses)
    if unique.isEmpty { return "draft" }
    if unique == ["pending"] { return "pending" }
    if unique == ["rejected"] { return "rejected" }
    if unique.allSatisfy({ ["delivered"].contains($0) }) { return "complete" }
    if unique.allSatisfy({ ["ordered", "received", "backorder", "staged", "delivered", "in_procurement"].contains($0) }) { return "ordered" }
    if unique.allSatisfy({ ["approved", "transfer", "in_procurement", "ordered", "received", "backorder", "staged", "delivered"].contains($0) }) { return "approved" }
    return "in_review"
}
```

### Step 5: Add smart routing on JPO line creation

When a line item is added to a JPO, check if the part is in stock and auto-route:

```swift
/// Check stock and auto-route a JPO line item.
/// Returns "transfer" if stock available, "pending" if needs ordering.
public func smartRouteJPOLine(lineId: Int64, partId: Int64, userId: Int64) throws -> String {
    return try db.writer.write { dbConn -> String in
        // Check shop stock
        let shopStock = try Int.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(qty), 0) FROM stock
            WHERE part_id = ? AND deleted_at IS NULL
            """, arguments: [partId]) ?? 0

        let requestedQty = try Int.fetchOne(dbConn, sql: """
            SELECT quantity FROM jpo_lines WHERE id = ?
            """, arguments: [lineId]) ?? 0

        if shopStock >= requestedQty {
            // In stock — auto-create transfer, no approval needed
            try dbConn.execute(
                sql: """
                    UPDATE jpo_lines SET line_status = 'transfer',
                    status_updated_at = datetime('now'), status_updated_by = ?
                    WHERE id = ?
                    """,
                arguments: [userId, lineId]
            )
            return "transfer"
        } else {
            // Needs ordering — requires approval
            try dbConn.execute(
                sql: """
                    UPDATE jpo_lines SET line_status = 'pending',
                    status_updated_at = datetime('now'), status_updated_by = ?
                    WHERE id = ?
                    """,
                arguments: [userId, lineId]
            )
            return "pending"
        }
    }
}
```

### Step 6: Call smart routing from addJPOLineItem

Update the existing `addJPOLineItem` method to call `smartRouteJPOLine` after inserting the line:

```swift
// After inserting the line item:
if let partId = partId {
    let userId = /* get current user ID */ 0 as Int64
    _ = try smartRouteJPOLine(lineId: newLineId, partId: partId, userId: userId)
}
```

### Step 7: Add to ConflictResolver whitelist

Add any new tables to the sync conflict resolver whitelist if needed.

## Important Notes

- The `line_status` field replaces the JPO-level status for decision-making. The JPO-level status is now DERIVED from its lines.
- Smart routing checks shop stock first. Future enhancement: also check user's truck stock.
- The `delivery_option` field ("partial" or "full") is set at creation and locked once any parts are delivered.
- `po_line_id` links a JPO line to the PO line it was consolidated into (set during procurement).
- `transfer_id` links to the stock_movement created for auto-transfers.
- `chat_thread_id` links to the chat thread created when a part is put on hold.
- Check the actual column name used in the jpo_lines table — it might be `jpo_line_items` or similar.

## Success Criteria

- [ ] Migration adds line_status, hold_reason, reject_reason, chat_thread_id, po_line_id, transfer_id to jpo_lines
- [ ] Migration adds delivery_option, delivery_locked to job_purchase_orders
- [ ] JPOLineRow struct updated with new fields
- [ ] Per-line status update method with auto-derive of parent JPO status
- [ ] Smart routing: stock check → "transfer" or "pending"
- [ ] Smart routing called on line item creation
- [ ] Migration registered in registerMigrations()
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 27B Results (YYYY-MM-DD)
- Migration 032: per-line status + delivery options
- Smart routing: shop stock check → auto-transfer vs pending approval
- Status derivation: JPO status derived from line statuses
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 27C.**
