# 16B — FIFO/LIFO Cost Engine Service Methods

> **Chain position:** 16A (migration) → **16B** → 16C (hierarchical pricing) → 16D–16I
> **Prerequisite:** 16A complete (tables: cost_layers, cost_layer_consumptions, price_history exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

WiredPart uses FIFO (First In, First Out) for selling inventory and LIFO (Last In, First Out) for returns. When parts arrive from a PO, each delivery creates a "cost layer" (batch) with a quantity and unit cost. When parts are consumed (sent to a job), the OLDEST batch is decremented first. When parts are returned from a job, the MOST RECENTLY consumed batch is restored first — as if the sale never happened.

**Example:**
- Day A: Buy 12 of item Q at $18 → batch [12×$18], avg = $18.00
- Day B: Buy 18 more at $5 → batches [12×$18] + [18×$5], avg = $10.20
- Sell 3 (FIFO): remove from oldest ($18 batch) → [9×$18] + [18×$5], avg = $9.33
- Return 1 (LIFO): restore to last-consumed batch ($18) → [10×$18] + [18×$5], avg = $9.64

The weighted average cost is company-wide (not per-location). It's calculated from ALL remaining cost layers for that part. Unit costs can have up to 5 decimal places ($0.00001 precision).

**Key files:**
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add methods in section `// MARK: - 5. Pricing`
- `core/Sources/WiredPartCore/Models/Costs/CostsModels.swift` — CostLayer, CostLayerConsumption, PriceHistory models
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — tables: cost_layers, cost_layer_consumptions

## Task

Add these methods to `PartsService.swift` inside the `// MARK: - 5. Pricing` section, AFTER the existing `updatePartPricing` method.

### Method 1: Add a cost layer (when parts arrive from a PO)

```swift
/// Record a new cost layer when parts are received from a purchase order.
/// Each delivery (even partial) creates its own batch with its own unit cost.
/// After adding, recalculates and updates the part's weighted average cost.
///
/// - Parameters:
///   - partId: The part receiving inventory
///   - qty: Number of units received
///   - unitCost: Cost per unit (up to 5 decimal precision)
///   - poLineId: Optional PO line item reference
///   - supplierId: Optional supplier reference for return tracking
/// - Returns: The created CostLayer
@discardableResult
public func addCostLayer(
    partId: Int64,
    qty: Int,
    unitCost: Double,
    poLineId: Int64? = nil,
    supplierId: Int64? = nil
) throws -> CostLayer {
    guard qty > 0 else { throw PartsError.invalidQuantity }

    let layer = try db.writer.write { dbConn -> CostLayer in
        var layer = CostLayer(
            partId: partId,
            purchaseDate: ISO8601DateFormatter().string(from: Date()),
            poLineId: poLineId,
            originalQty: qty,
            remainingQty: qty,
            unitCost: unitCost
        )
        try layer.insert(dbConn)
        return layer
    }

    // Recalculate weighted average cost
    try recalculateWeightedAvgCost(partId: partId)

    // Log price history
    try logPriceChange(
        partId: partId,
        changeType: "cost_update",
        newValue: unitCost,
        source: poLineId != nil ? "receiving" : "manual",
        sourceId: poLineId
    )

    return layer
}
```

### Method 2: Consume inventory (FIFO — sell/use parts on a job)

```swift
/// Consume parts using FIFO ordering — oldest batches are used first.
/// Creates consumption records for return tracking.
///
/// - Parameters:
///   - partId: The part being consumed
///   - qty: Number of units to consume
///   - jobId: Optional job the parts are going to
///   - sellPrice: Price charged to the customer per unit
/// - Returns: Array of consumption records created
@discardableResult
public func consumeInventoryFIFO(
    partId: Int64,
    qty: Int,
    jobId: Int64? = nil,
    sellPrice: Double? = nil
) throws -> [CostLayerConsumption] {
    guard qty > 0 else { throw PartsError.invalidQuantity }

    let consumptions = try db.writer.write { dbConn -> [CostLayerConsumption] in
        // Get all non-empty layers for this part, oldest first (FIFO)
        let layers = try CostLayer.fetchAll(dbConn, sql: """
            SELECT * FROM cost_layers
            WHERE part_id = ? AND remaining_qty > 0
            ORDER BY purchase_date ASC, id ASC
            """, arguments: [partId])

        // Check total available
        let totalAvailable = layers.reduce(0) { $0 + $1.remainingQty }
        guard totalAvailable >= qty else {
            throw PartsError.insufficientStock(available: totalAvailable, requested: qty)
        }

        var remaining = qty
        var records: [CostLayerConsumption] = []

        for var layer in layers {
            guard remaining > 0 else { break }

            let take = min(remaining, layer.remainingQty)

            // Decrement the layer
            layer.remainingQty -= take
            try layer.update(dbConn)

            // Find the supplier from the PO line if available
            var supplierId: Int64? = nil
            if let poLineId = layer.poLineId {
                let row = try Row.fetchOne(dbConn, sql: """
                    SELECT po.supplier_id FROM po_line_items pli
                    JOIN purchase_orders po ON po.id = pli.po_id
                    WHERE pli.id = ?
                    """, arguments: [poLineId])
                supplierId = row?["supplier_id"] as? Int64
            }

            // Create consumption record
            var consumption = CostLayerConsumption(
                costLayerId: layer.id!,
                partId: partId,
                jobId: jobId,
                qtyConsumed: take,
                unitCostAtSale: layer.unitCost,
                sellPriceCharged: sellPrice,
                supplierId: supplierId,
                isReturned: 0
            )
            try consumption.insert(dbConn)
            records.append(consumption)

            remaining -= take
        }

        return records
    }

    // Recalculate weighted average after consumption
    try recalculateWeightedAvgCost(partId: partId)

    return consumptions
}
```

### Method 3: Return inventory (LIFO — restore most recently consumed)

```swift
/// Return parts using LIFO — most recently consumed batches are restored first.
/// Marks consumption records as returned and restores batch quantities.
/// The returned parts go back as if they never left.
///
/// - Parameters:
///   - partId: The part being returned
///   - qty: Number of units to return
///   - jobId: Optional job the parts are coming back from
/// - Returns: Array of consumption records that were reversed
@discardableResult
public func returnInventoryLIFO(
    partId: Int64,
    qty: Int,
    jobId: Int64? = nil
) throws -> [CostLayerConsumption] {
    guard qty > 0 else { throw PartsError.invalidQuantity }

    let reversed = try db.writer.write { dbConn -> [CostLayerConsumption] in
        // Find un-returned consumptions for this part, most recent first (LIFO)
        var sql = """
            SELECT * FROM cost_layer_consumptions
            WHERE part_id = ? AND is_returned = 0
            """
        var args: [any DatabaseValueConvertible] = [partId]
        if let jobId {
            sql += " AND job_id = ?"
            args.append(jobId)
        }
        sql += " ORDER BY created_at DESC, id DESC"

        let consumptions = try CostLayerConsumption.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))

        let totalReturnable = consumptions.reduce(0) { $0 + $1.qtyConsumed }
        guard totalReturnable >= qty else {
            throw PartsError.insufficientReturns(available: totalReturnable, requested: qty)
        }

        var remaining = qty
        var records: [CostLayerConsumption] = []
        let now = ISO8601DateFormatter().string(from: Date())

        for var consumption in consumptions {
            guard remaining > 0 else { break }

            let restore = min(remaining, consumption.qtyConsumed)

            // Restore the cost layer
            if var layer = try CostLayer.fetchOne(dbConn, key: consumption.costLayerId) {
                layer.remainingQty += restore
                try layer.update(dbConn)
            }

            // Mark consumption as returned
            if restore == consumption.qtyConsumed {
                // Full return of this consumption
                consumption.isReturned = 1
                consumption.returnedAt = now
                try consumption.update(dbConn)
            } else {
                // Partial return: split the consumption record
                // Reduce original consumption qty
                consumption.qtyConsumed -= restore
                try consumption.update(dbConn)

                // Create a new "returned" record for the restored portion
                var returnedRecord = consumption
                returnedRecord.id = nil
                returnedRecord.qtyConsumed = restore
                returnedRecord.isReturned = 1
                returnedRecord.returnedAt = now
                try returnedRecord.insert(dbConn)
            }

            records.append(consumption)
            remaining -= restore
        }

        return records
    }

    // Recalculate weighted average after return
    try recalculateWeightedAvgCost(partId: partId)

    return reversed
}
```

### Method 4: Recalculate weighted average cost

```swift
/// Recalculate and store the weighted average cost for a part from its cost layers.
/// weighted_avg = Σ(remaining_qty × unit_cost) / Σ(remaining_qty)
/// This is company-wide — location doesn't matter for pricing.
public func recalculateWeightedAvgCost(partId: Int64) throws {
    try db.writer.write { dbConn in
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT
                COALESCE(SUM(remaining_qty * unit_cost), 0) AS total_value,
                COALESCE(SUM(remaining_qty), 0) AS total_qty
            FROM cost_layers
            WHERE part_id = ? AND remaining_qty > 0
            """, arguments: [partId])

        let totalValue: Double = row?["total_value"] ?? 0
        let totalQty: Int = row?["total_qty"] ?? 0
        let weightedAvg = totalQty > 0 ? totalValue / Double(totalQty) : 0

        try dbConn.execute(
            sql: """
                UPDATE parts SET weighted_avg_cost = ?, updated_at = datetime('now')
                WHERE id = ?
                """,
            arguments: [weightedAvg, partId]
        )
    }
}
```

### Method 5: Get cost layers for a part

```swift
/// Get all cost layers (batches) for a part, optionally filtering to non-empty only.
public func getCostLayers(partId: Int64, nonEmptyOnly: Bool = false) throws -> [CostLayer] {
    try db.writer.read { dbConn in
        var sql = "SELECT * FROM cost_layers WHERE part_id = ?"
        if nonEmptyOnly {
            sql += " AND remaining_qty > 0"
        }
        sql += " ORDER BY purchase_date ASC, id ASC"
        return try CostLayer.fetchAll(dbConn, sql: sql, arguments: [partId])
    }
}

/// Get consumption history for a part, optionally filtered by job.
public func getConsumptionHistory(partId: Int64, jobId: Int64? = nil) throws -> [CostLayerConsumption] {
    try db.writer.read { dbConn in
        var sql = "SELECT * FROM cost_layer_consumptions WHERE part_id = ?"
        var args: [any DatabaseValueConvertible] = [partId]
        if let jobId {
            sql += " AND job_id = ?"
            args.append(jobId)
        }
        sql += " ORDER BY created_at DESC"
        return try CostLayerConsumption.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
    }
}
```

### Method 6: Reset to current buy price

```swift
/// Reset all cost layers for a part to the current (most recent) buy price.
/// Collapses all batches into one layer at the new price.
/// Returns (oldAvg, newAvg) so the caller can show the difference.
public func resetToCurrent BuyPrice(partId: Int64) throws -> (oldAvg: Double, newAvg: Double) {
    try db.writer.write { dbConn in
        // Get current weighted average
        let currentRow = try Row.fetchOne(dbConn, sql: """
            SELECT weighted_avg_cost FROM parts WHERE id = ?
            """, arguments: [partId])
        let oldAvg: Double = currentRow?["weighted_avg_cost"] ?? 0

        // Get most recent cost layer price
        let recentRow = try Row.fetchOne(dbConn, sql: """
            SELECT unit_cost FROM cost_layers
            WHERE part_id = ? AND remaining_qty > 0
            ORDER BY purchase_date DESC, id DESC
            LIMIT 1
            """, arguments: [partId])
        let currentBuyPrice: Double = recentRow?["unit_cost"] ?? oldAvg

        // Get total remaining inventory
        let qtyRow = try Row.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(remaining_qty), 0) AS total
            FROM cost_layers WHERE part_id = ? AND remaining_qty > 0
            """, arguments: [partId])
        let totalQty: Int = qtyRow?["total"] ?? 0

        if totalQty > 0 {
            // Soft-delete all existing layers
            try dbConn.execute(sql: """
                UPDATE cost_layers SET remaining_qty = 0
                WHERE part_id = ? AND remaining_qty > 0
                """, arguments: [partId])

            // Create one new layer at current buy price
            try dbConn.execute(sql: """
                INSERT INTO cost_layers (part_id, purchase_date, original_qty, remaining_qty, unit_cost)
                VALUES (?, datetime('now'), ?, ?, ?)
                """, arguments: [partId, totalQty, totalQty, currentBuyPrice])

            // Update weighted average
            try dbConn.execute(sql: """
                UPDATE parts SET weighted_avg_cost = ?, cost_last_updated = datetime('now'), updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [currentBuyPrice, partId])
        }

        return (oldAvg, currentBuyPrice)
    }
}
```

### Method 7: Log price changes

```swift
/// Log a price change to the history table for auditing.
public func logPriceChange(
    partId: Int64? = nil,
    pricingTierId: Int64? = nil,
    changeType: String,
    oldValue: Double? = nil,
    newValue: Double? = nil,
    oldSellPrice: Double? = nil,
    newSellPrice: Double? = nil,
    source: String? = nil,
    sourceId: Int64? = nil,
    changedBy: Int64? = nil
) throws {
    try db.writer.write { dbConn in
        var record = PriceHistory(
            partId: partId,
            pricingTierId: pricingTierId,
            changeType: changeType,
            oldValue: oldValue,
            newValue: newValue,
            oldSellPrice: oldSellPrice,
            newSellPrice: newSellPrice,
            source: source,
            sourceId: sourceId,
            changedBy: changedBy
        )
        try record.insert(dbConn)
    }
}

/// Get price change history for a part.
public func getPriceHistory(partId: Int64, limit: Int = 50) throws -> [PriceHistory] {
    try db.writer.read { dbConn in
        try PriceHistory.fetchAll(dbConn, sql: """
            SELECT * FROM price_history
            WHERE part_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """, arguments: [partId, limit])
    }
}
```

### Step 2: Add error cases to PartsError

Find the `PartsError` enum (or `enum PartsError` section) and add:

```swift
case invalidQuantity
case insufficientStock(available: Int, requested: Int)
case insufficientReturns(available: Int, requested: Int)
```

Also add matching `localizedDescription` cases if a computed property exists.

### Important Notes

- The method name `resetToCurrent BuyPrice` has a space — fix it to `resetToCurrentBuyPrice` (remove the space).
- All methods use `db.writer.write` or `db.writer.read` — consistent with existing patterns.
- Unit costs support Double precision (5 decimal places happen naturally).
- FIFO order: `ORDER BY purchase_date ASC, id ASC` (oldest first).
- LIFO order for returns: `ORDER BY created_at DESC, id DESC` (most recent first).

## Success Criteria

- [ ] 7 new methods added to PartsService: addCostLayer, consumeInventoryFIFO, returnInventoryLIFO, recalculateWeightedAvgCost, getCostLayers, getConsumptionHistory, resetToCurrentBuyPrice, logPriceChange, getPriceHistory
- [ ] Error cases added to PartsError
- [ ] Weighted average recalculated after every add/consume/return
- [ ] Consumption records created during FIFO sell with supplier tracking
- [ ] LIFO returns restore batches as if the sale never happened
- [ ] Price reset collapses all layers to one at current buy price
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16B Results (YYYY-MM-DD)
- Methods added: addCostLayer, consumeInventoryFIFO, returnInventoryLIFO, recalculateWeightedAvgCost, getCostLayers, getConsumptionHistory, resetToCurrentBuyPrice, logPriceChange, getPriceHistory
- Error cases: invalidQuantity, insufficientStock, insufficientReturns
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16C.**
