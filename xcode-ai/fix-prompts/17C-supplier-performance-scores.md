# 17C — Auto-Calculated Supplier Performance Scores

> **Chain position:** 17A → 17B → **17C** → 17D–17H
> **Prerequisite:** 17B complete (supplier form with all fields)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Supplier performance scores (quality, on-time rate, reliability) currently show in the supplier list but can't be set and aren't calculated from real data. These should be auto-calculated from:

- **Quality Score:** Based on return rate — fewer returns = higher quality. `100 - (returns / total_received × 100)`
- **On-Time Rate:** Based on PO delivery timeliness — `orders_on_time / total_orders × 100`. An order is "on time" if received within the expected delivery window.
- **Reliability Score:** Average of quality and on-time rate, weighted. Suppliers who consistently deliver = reliable.

These scores should recalculate whenever receiving data changes (new PO received, return processed).

**Key files:**
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add calculation methods
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — update display

## Task

### Step 1: Add performance score calculation methods to PartsService

```swift
// =========================================================================
// MARK: - 11. Supplier Performance Scores
// =========================================================================

/// Calculated performance scores for a supplier.
public struct SupplierScores: Sendable {
    public let qualityScore: Double       // 0-100, based on return rate
    public let onTimeRate: Double          // 0-100, based on delivery timeliness
    public let reliabilityScore: Double    // 0-100, weighted average
    public let totalOrderCount: Int        // total POs to this supplier
    public let totalUnitsReceived: Int     // total units received
    public let totalUnitsReturned: Int     // total units returned to supplier
    public let avgDeliveryDays: Double?    // average days from PO creation to receiving
}

/// Calculate performance scores for a supplier based on actual PO/receiving data.
public func calculateSupplierScores(supplierId: Int64) throws -> SupplierScores {
    try db.writer.read { dbConn in
        // Count total POs and received POs for this supplier
        let poRow = try Row.fetchOne(dbConn, sql: """
            SELECT
                COUNT(*) AS total_pos,
                COUNT(CASE WHEN status IN ('received', 'completed', 'closed') THEN 1 END) AS received_pos
            FROM purchase_orders
            WHERE supplier_id = ? AND deleted_at IS NULL
            """, arguments: [supplierId])
        let totalPOs: Int = poRow?["total_pos"] ?? 0
        let receivedPOs: Int = poRow?["received_pos"] ?? 0

        // Total units received from this supplier (from receiving sessions or stock movements)
        let receivedRow = try Row.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(qty), 0) AS total_received
            FROM stock_movements
            WHERE supplier_id = ? AND movement_type = 'receipt' AND deleted_at IS NULL
            """, arguments: [supplierId])
        let totalReceived: Int = receivedRow?["total_received"] ?? 0

        // Total units returned TO this supplier
        let returnedRow = try Row.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(qty), 0) AS total_returned
            FROM stock_movements
            WHERE supplier_id = ? AND movement_type = 'return' AND deleted_at IS NULL
            AND from_location_type IN ('warehouse', 'staging')
            AND to_location_type = 'supplier'
            """, arguments: [supplierId])
        let totalReturned: Int = returnedRow?["total_returned"] ?? 0

        // Quality score: 100 - (return_rate %)
        let qualityScore: Double
        if totalReceived > 0 {
            let returnRate = (Double(totalReturned) / Double(totalReceived)) * 100
            qualityScore = max(0, min(100, 100 - returnRate))
        } else {
            qualityScore = 0 // no data
        }

        // On-time rate: POs with receiving_sessions completed within expected days
        // Compare PO created_at + expected_delivery_days vs actual receiving date
        let onTimeRow = try Row.fetchOne(dbConn, sql: """
            SELECT
                COUNT(*) AS total_received_pos,
                COUNT(CASE
                    WHEN rs.completed_at IS NOT NULL
                    AND julianday(rs.completed_at) - julianday(po.created_at) <= COALESCE(s.delivery_days_numeric, 14)
                    THEN 1 END) AS on_time_count
            FROM purchase_orders po
            LEFT JOIN receiving_sessions rs ON rs.po_id = po.id AND rs.status = 'complete'
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            WHERE po.supplier_id = ? AND po.deleted_at IS NULL
            AND po.status IN ('received', 'completed', 'closed')
            """, arguments: [supplierId])
        let totalReceivedPOs: Int = onTimeRow?["total_received_pos"] ?? 0
        let onTimeCount: Int = onTimeRow?["on_time_count"] ?? 0

        let onTimeRate: Double
        if totalReceivedPOs > 0 {
            onTimeRate = (Double(onTimeCount) / Double(totalReceivedPOs)) * 100
        } else {
            onTimeRate = 0
        }

        // Average delivery days
        let avgDaysRow = try Row.fetchOne(dbConn, sql: """
            SELECT AVG(julianday(rs.completed_at) - julianday(po.created_at)) AS avg_days
            FROM purchase_orders po
            JOIN receiving_sessions rs ON rs.po_id = po.id AND rs.status = 'complete'
            WHERE po.supplier_id = ? AND po.deleted_at IS NULL
            AND rs.completed_at IS NOT NULL
            """, arguments: [supplierId])
        let avgDays: Double? = avgDaysRow?["avg_days"]

        // Reliability: weighted average (60% on-time, 40% quality)
        let reliabilityScore: Double
        if totalPOs > 0 {
            reliabilityScore = (onTimeRate * 0.6) + (qualityScore * 0.4)
        } else {
            reliabilityScore = 0
        }

        return SupplierScores(
            qualityScore: qualityScore,
            onTimeRate: onTimeRate,
            reliabilityScore: reliabilityScore,
            totalOrderCount: totalPOs,
            totalUnitsReceived: totalReceived,
            totalUnitsReturned: totalReturned,
            avgDeliveryDays: avgDays
        )
    }
}

/// Recalculate and persist supplier scores to the suppliers table.
/// Call this after receiving, returns, or PO status changes.
public func updateSupplierScores(supplierId: Int64) throws {
    let scores = try calculateSupplierScores(supplierId: supplierId)
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE suppliers SET
                quality_score = ?,
                on_time_rate = ?,
                reliability_score = ?,
                updated_at = datetime('now')
            WHERE id = ?
            """, arguments: [scores.qualityScore, scores.onTimeRate, scores.reliabilityScore, supplierId])
    }
}

/// Recalculate scores for ALL suppliers. Use sparingly (e.g., monthly batch job).
public func recalculateAllSupplierScores() throws {
    let suppliers = try db.writer.read { dbConn in
        try Row.fetchAll(dbConn, sql: "SELECT id FROM suppliers WHERE deleted_at IS NULL")
    }
    for row in suppliers {
        let id: Int64 = row["id"]
        try updateSupplierScores(supplierId: id)
    }
}
```

### Step 2: Add delivery_days_numeric helper

The on-time calculation references `s.delivery_days_numeric` but the suppliers table has `delivery_days` as TEXT (e.g., "Mon-Fri", "Next Day", "3-5 Business Days"). We need a numeric fallback.

Option A: Add a computed approach in the SQL using CASE:
```sql
COALESCE(
    CAST(s.delivery_days AS INTEGER),  -- works if delivery_days is just a number
    14  -- default to 14 days if not parseable
)
```

Replace `s.delivery_days_numeric` in the query with this COALESCE expression.

Option B (preferred): Add a `delivery_days_estimate` INTEGER column in migration 026. Update 17A's migration to include:
```swift
try db.alter(table: "suppliers") { t in
    t.add(column: "account_number", .text)
    t.add(column: "delivery_days_estimate", .integer)  // estimated delivery days for on-time calc
}
```

If you go with Option B, also add `deliveryDaysEstimate: Int?` to the Supplier model and an input field in the form.

### Step 3: Update the supplier list to show calculated scores

In `PartsSuppliersPage.swift`, update `loadData()` to calculate scores:

After mapping suppliers, add:
```swift
// Recalculate scores for displayed suppliers
for i in rows.indices {
    if let scores = try? service.calculateSupplierScores(supplierId: rows[i].id) {
        rows[i] = SupplierListRow(
            // ... copy all existing fields ...
            qualityScore: scores.qualityScore,
            onTimeRate: scores.onTimeRate,
            reliabilityScore: scores.reliabilityScore
            // ... remaining fields ...
        )
    }
}
```

Or better: add a `var` quality/on-time/reliability to SupplierListRow and update in-place.

### Step 4: Update SupplierDetailSheet to show score breakdown

In the "Performance Scores" section of `SupplierDetailSheet`, add detail:

```swift
Section("Performance Scores") {
    // Load live scores
    if let scores = supplierScores {
        LabeledContent("Quality") {
            HStack(spacing: 4) {
                Text(String(format: "%.0f%%", scores.qualityScore))
                    .foregroundStyle(scoreColor(scores.qualityScore))
                    .fontWeight(.bold)
            }
        }
        if scores.totalUnitsReceived > 0 {
            Text("\(scores.totalUnitsReturned) returned of \(scores.totalUnitsReceived) received")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        LabeledContent("On-Time Rate") {
            Text(String(format: "%.0f%%", scores.onTimeRate))
                .foregroundStyle(scoreColor(scores.onTimeRate))
                .fontWeight(.bold)
        }
        if let avgDays = scores.avgDeliveryDays {
            Text(String(format: "Avg delivery: %.1f days", avgDays))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Reliability") {
            Text(String(format: "%.0f%%", scores.reliabilityScore))
                .foregroundStyle(scoreColor(scores.reliabilityScore))
                .fontWeight(.bold)
        }

        LabeledContent("Total Orders", value: "\(scores.totalOrderCount)")
    } else {
        Text("No order data yet — scores will appear after the first PO is received.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

Add state:
```swift
@State private var supplierScores: PartsService.SupplierScores?
```

Load in `.task`:
```swift
if let service = appCore.partsService {
    supplierScores = try? service.calculateSupplierScores(supplierId: supplier.id)
}
```

## Important Notes

- Scores show 0% when there's no data (no POs yet). The detail view should explain this: "No order data yet."
- The on-time calculation assumes `receiving_sessions.completed_at` exists. If the column name is different, adjust.
- Quality score = inverse of return rate. A 2% return rate = 98% quality.
- Reliability = 60% on-time weight + 40% quality weight. This can be tuned later.
- `recalculateAllSupplierScores()` is for batch jobs, not per-page-load.

## Success Criteria

- [ ] `calculateSupplierScores` computes quality, on-time, reliability from actual data
- [ ] `updateSupplierScores` persists scores to the suppliers table
- [ ] Quality based on return rate from stock_movements
- [ ] On-time based on PO created_at vs receiving completed_at
- [ ] Reliability = weighted average of quality + on-time
- [ ] Detail sheet shows score breakdown with data context
- [ ] Scores show 0% with explanation when no data exists
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17C Results (YYYY-MM-DD)
- Service: calculateSupplierScores, updateSupplierScores, recalculateAllSupplierScores
- SupplierScores struct: quality, onTime, reliability, counts, avgDays
- Detail sheet: score breakdown with return counts and delivery stats
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17D.**
