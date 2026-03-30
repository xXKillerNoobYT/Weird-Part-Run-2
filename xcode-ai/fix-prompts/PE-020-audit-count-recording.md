# PE-020: Fix Audit Count Recording & Discrepancy Calculation

**Severity:** CRITICAL — Audits currently record no physical counts, report 0 discrepancies, and show meaningless summary metrics

---

## Problem

Three tightly-related bugs in `core/Sources/WiredPartCore/Services/WarehouseService.swift`:

### Bug B4 — `recordAuditCount()` discards the counted quantity
```swift
// Current (wrong):
try dbConn.execute(
    sql: "UPDATE stock SET last_counted = datetime('now') WHERE id = ?",
    arguments: [stockId]
)
// countedQty parameter is accepted but never stored.
```

### Bug B1 — `getAuditDiscrepancies()` hardcodes 0 difference
```swift
return AuditDiscrepancy(
    ...
    systemQty: qty,
    countedQty: qty,   // ← same value as systemQty
    difference: 0,     // ← always 0
    ...
)
```

### Bug B2 — `getAuditSummary()` uses wrong "discrepancies" count
```swift
// "discrepancies" is just "items counted today" — completely wrong metric
let discrepancies = try safeCount(sql: """
    SELECT COUNT(*) FROM stock WHERE ... AND date(last_counted) = date('now')
""")
```

---

## Root Cause

There is no persistent storage for `counted_qty`. The `stock` table only holds the live system quantity (`qty`). We need a new migration and column to store what the user physically counted.

---

## Fix

### Step 1 — Add migration in `AppDatabase+Migrations.swift`

Register a new migration (next available number after 040+). Check the existing highest migration number first. Add:

```swift
private static func registerMigrationXXXAuditCounts(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("XXX_audit_counted_qty") { db in
        // Add counted_qty column to stock table to persist physical counts
        try db.alter(table: "stock") { t in
            t.add(column: "counted_qty", .integer)
        }
    }
}
```

Register it in the `registerAllMigrations` function in the same file.

### Step 2 — Fix `recordAuditCount()` in `WarehouseService.swift`

```swift
public func recordAuditCount(
    stockId: Int64,
    countedQty: Int
) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(
            sql: """
                UPDATE stock
                SET last_counted = datetime('now'),
                    counted_qty  = ?
                WHERE id = ? AND deleted_at IS NULL
                """,
            arguments: [countedQty, stockId]
        )
    }
}
```

### Step 3 — Fix `getAuditDiscrepancies()` in `WarehouseService.swift`

Read `counted_qty` from the row and compute the real difference:

```swift
public func getAuditDiscrepancies() throws -> [AuditDiscrepancy] {
    do {
        return try db.writer.read { dbConn -> [AuditDiscrepancy] in
            let rows = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT s.part_id, s.location_type, s.location_id,
                           s.qty, s.counted_qty, s.last_counted,
                           p.name AS part_name, p.code AS part_code
                    FROM stock s
                    LEFT JOIN parts p ON p.id = s.part_id
                    WHERE s.location_type = 'warehouse'
                      AND s.deleted_at IS NULL
                      AND s.last_counted IS NOT NULL
                      AND date(s.last_counted) = date('now')
                      AND s.counted_qty IS NOT NULL
                    ORDER BY p.name
                    """
            )
            return rows.compactMap { row -> AuditDiscrepancy? in
                let partId: Int64 = row["part_id"] ?? 0
                let systemQty: Int = row["qty"] ?? 0
                let countedQty: Int = row["counted_qty"] ?? systemQty

                return AuditDiscrepancy(
                    partId: partId,
                    partName: (row["part_name"] as String?) ?? "Unknown Part",
                    partCode: row["part_code"] as String?,
                    locationType: row["location_type"] ?? "warehouse",
                    locationId: row["location_id"] ?? 1,
                    systemQty: systemQty,
                    countedQty: countedQty,
                    difference: countedQty - systemQty,
                    lastCounted: row["last_counted"] as String?
                )
            }
        }
    } catch {
        if isTableNotFoundError(error) { return [] }
        throw error
    }
}
```

### Step 4 — Fix `getAuditSummary()` in `WarehouseService.swift`

Count actual discrepancies (where counted_qty ≠ qty):

```swift
public func getAuditSummary() throws -> AuditSummary {
    let totalParts = try safeCount(
        sql: """
            SELECT COUNT(DISTINCT part_id) FROM stock
            WHERE location_type = 'warehouse' AND deleted_at IS NULL AND qty > 0
            """
    )

    let countedParts = try safeCount(
        sql: """
            SELECT COUNT(DISTINCT part_id) FROM stock
            WHERE location_type = 'warehouse' AND deleted_at IS NULL
              AND last_counted IS NOT NULL
              AND date(last_counted) = date('now')
              AND counted_qty IS NOT NULL
            """
    )

    let discrepancies = try safeCount(
        sql: """
            SELECT COUNT(*) FROM stock
            WHERE location_type = 'warehouse' AND deleted_at IS NULL
              AND last_counted IS NOT NULL
              AND date(last_counted) = date('now')
              AND counted_qty IS NOT NULL
              AND counted_qty != qty
            """
    )

    let lastDate: String? = try? db.writer.read { dbConn in
        try String.fetchOne(
            dbConn,
            sql: """
                SELECT MAX(last_counted) FROM stock
                WHERE last_counted IS NOT NULL AND deleted_at IS NULL
                """
        )
    }

    return AuditSummary(
        totalParts: totalParts,
        countedParts: countedParts,
        discrepancies: discrepancies,
        lastAuditDate: lastDate ?? nil
    )
}
```

---

## Tests to Add

In `core/Tests/WiredPartCoreTests/WarehouseAuditTests.swift`, add:

1. `recordAuditCount_persistsCountedQty` — calls `recordAuditCount(stockId:, countedQty: 5)`, reads back the stock row, asserts `counted_qty == 5`.
2. `getAuditDiscrepancies_returnsNonZeroDifference` — sets up a stock row with `qty = 10`, records audit count of `7`, asserts discrepancy has `difference == -3`.
3. `getAuditSummary_countsRealDiscrepancies` — sets up 3 stock rows, records 2 matching counts and 1 mismatch, asserts `discrepancies == 1`.

---

## Verification

After changes:
1. `swift build` in `core/` — 0 errors
2. `swift test` — all existing tests pass + new audit tests pass
3. In simulator: perform an audit, enter a quantity, verify the counted value persists and the discrepancy shows correctly in the audit summary
