# 16G — Stale Price Alerts + Receiving Price Verification

> **Chain position:** 16A–16F → **16G** → 16H → 16I
> **Prerequisite:** 16F complete (pricing settings with stale_price_threshold_days)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Two features:

1. **Stale Price Alerts:** Parts not updated in X days (default 90, configurable in settings) should be flagged with a warning when they appear on orders. When ordering a stale part, show a banner: "Price hasn't been verified in X days — check the receipt when it arrives."

2. **Receiving Price Verification:** When receiving parts (IOSReceiveShipmentPage), ask the user for each line item: "Does the price match the order?" with three options:
   - **Matches** — price confirmed, update `cost_last_updated`
   - **Different** — prompt for new price, create new cost layer at actual price
   - **Not shown on receipt** — skip, don't update timestamp

This creates cost layers automatically during receiving, which feeds the FIFO system.

**Key files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`
- Add service method to `core/Sources/WiredPartCore/Services/PartsService.swift`
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` (stale badge on line items)

## Task

### Step 1: Add stale-check helper to PartsService

In `core/Sources/WiredPartCore/Services/PartsService.swift`, add after the pricing methods:

```swift
// =========================================================================
// MARK: - 5c. Stale Price Detection
// =========================================================================

/// Check if a part's price is stale (not updated within the threshold).
public func isPartPriceStale(partId: Int64) throws -> Bool {
    try db.writer.read { dbConn in
        let thresholdDays = Int(try getCompanySetting(dbConn: dbConn, key: "stale_price_threshold_days") ?? "90") ?? 90

        let row = try Row.fetchOne(dbConn, sql: """
            SELECT cost_last_updated FROM parts WHERE id = ? AND deleted_at IS NULL
            """, arguments: [partId])

        guard let lastUpdated: String = row?["cost_last_updated"],
              let date = ISO8601DateFormatter().date(from: lastUpdated) else {
            return true // never updated = stale
        }

        let daysSinceUpdate = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return daysSinceUpdate > thresholdDays
    }
}

/// Get all parts with stale pricing. Useful for reports and alerts.
public func getStalePricedParts(limit: Int = 100) throws -> [(partId: Int64, name: String, daysSinceUpdate: Int)] {
    try db.writer.read { dbConn in
        let thresholdDays = Int(try getCompanySetting(dbConn: dbConn, key: "stale_price_threshold_days") ?? "90") ?? 90

        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT id, name, cost_last_updated FROM parts
            WHERE deleted_at IS NULL
            AND (
                cost_last_updated IS NULL
                OR julianday('now') - julianday(cost_last_updated) > ?
            )
            ORDER BY cost_last_updated ASC NULLS FIRST
            LIMIT ?
            """, arguments: [thresholdDays, limit])

        return rows.map { row in
            let partId: Int64 = row["id"]
            let name: String = row["name"]
            let lastUpdated: String? = row["cost_last_updated"]
            let days: Int
            if let lu = lastUpdated, let date = ISO8601DateFormatter().date(from: lu) {
                days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
            } else {
                days = 999
            }
            return (partId: partId, name: name, daysSinceUpdate: days)
        }
    }
}

/// Mark a part's cost as verified (update the timestamp without changing the price).
public func markPriceVerified(partId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE parts SET cost_last_updated = datetime('now'), updated_at = datetime('now')
            WHERE id = ?
            """, arguments: [partId])
    }
}
```

### Step 2: Add receiving price verification to IOSReceiveShipmentPage

Find the file `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`.

For each line item in the receiving flow, add a **price verification section** after the quantity fields. Add these state variables:

```swift
@State private var priceVerifications: [Int64: PriceVerification] = [:] // lineItemId -> verification

enum PriceVerification {
    case matches
    case different(newPrice: Double)
    case notShown
}
```

For each line item row, add below the quantity input:

```swift
// Price verification
VStack(alignment: .leading, spacing: 8) {
    Text("Price on receipt?")
        .font(.caption)
        .foregroundStyle(.secondary)

    let lineId = lineItem.id ?? 0
    let currentVerification = priceVerifications[lineId]

    HStack(spacing: 8) {
        Button {
            priceVerifications[lineId] = .matches
        } label: {
            Label("Matches", systemImage: currentVerification.isMatches ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(currentVerification.isMatches ? Color.green.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
            priceVerifications[lineId] = .different(newPrice: 0)
        } label: {
            Label("Different", systemImage: currentVerification.isDifferent ? "exclamationmark.circle.fill" : "circle")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(currentVerification.isDifferent ? Color.orange.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
            priceVerifications[lineId] = .notShown
        } label: {
            Label("Not Shown", systemImage: currentVerification.isNotShown ? "questionmark.circle.fill" : "circle")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(currentVerification.isNotShown ? Color.secondary.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // New price input when "Different" is selected
    if case .different = currentVerification {
        HStack {
            Text("Actual price: $")
                .font(.caption)
            TextField("0.00", text: Binding(
                get: {
                    if case .different(let p) = priceVerifications[lineId] {
                        return p > 0 ? String(format: "%.5f", p) : ""
                    }
                    return ""
                },
                set: { newVal in
                    priceVerifications[lineId] = .different(newPrice: Double(newVal) ?? 0)
                }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 120)
        }
    }
}
```

Add helper extension for the verification enum:

```swift
extension Optional where Wrapped == PriceVerification {
    var isMatches: Bool {
        if case .matches = self { return true }
        return false
    }
    var isDifferent: Bool {
        if case .different = self { return true }
        return false
    }
    var isNotShown: Bool {
        if case .notShown = self { return true }
        return false
    }
}
```

### Step 3: Process verifications on save

In the receive completion handler (when the user taps "Complete Receiving" or similar), add this after updating quantities:

```swift
// Process price verifications → create cost layers
if let partsService = appCore.partsService {
    for (lineId, verification) in priceVerifications {
        // Find the line item's part_id and order price
        guard let lineItem = receivingItems.first(where: { ($0.poLineId ?? 0) == lineId || ($0.id ?? 0) == lineId }),
              let partId = lineItem.partId else { continue }

        let receivedQty = lineItem.receivedQty
        guard receivedQty > 0 else { continue }

        switch verification {
        case .matches:
            // Use order price, mark as verified
            let orderPrice = lineItem.unitPrice ?? 0
            if orderPrice > 0 {
                try? partsService.addCostLayer(
                    partId: partId,
                    qty: receivedQty,
                    unitCost: orderPrice,
                    poLineId: lineId
                )
            }
            try? partsService.markPriceVerified(partId: partId)

        case .different(let newPrice):
            // Use actual receipt price, create cost layer at new price
            if newPrice > 0 {
                try? partsService.addCostLayer(
                    partId: partId,
                    qty: receivedQty,
                    unitCost: newPrice,
                    poLineId: lineId
                )
                try? partsService.markPriceVerified(partId: partId)
            }

        case .notShown:
            // Don't update cost_last_updated, don't create cost layer from this receiving
            // The part keeps its existing weighted average
            break
        }
    }
}
```

### Step 4: Add stale badge to PO detail page line items

In `IOSPODetailPage.swift`, for each line item that references a part, check staleness and show a small warning:

```swift
// After the part name in the line item row:
if let partId = lineItem.partId,
   let service = appCore.partsService,
   (try? service.isPartPriceStale(partId: partId)) == true {
    HStack(spacing: 4) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
        Text("Price not verified recently")
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}
```

## Important Notes

- The `PriceVerification` enum and its optional extension should be private to the receiving page file or in a shared location if used elsewhere.
- `addCostLayer` from 16B automatically recalculates weighted average cost.
- The stale check uses `julianday()` for SQLite date math — this is reliable for day-level comparisons.
- Cost precision: up to 5 decimal places ($0.00001).
- When "Different" is selected, the text field allows 5 decimal places via format string.
- The `lineItem.partId` and `lineItem.unitPrice` field names may differ — check the actual ReceivingSessionItem or POLineItem model and adjust accordingly.

## Success Criteria

- [ ] `isPartPriceStale` returns true for parts not updated in > threshold days
- [ ] `getStalePricedParts` returns a list for reporting
- [ ] `markPriceVerified` updates timestamp without changing price
- [ ] Receiving flow shows 3-option price verification per line item
- [ ] "Matches" creates cost layer at order price + marks verified
- [ ] "Different" prompts for actual price + creates cost layer at new price
- [ ] "Not Shown" skips entirely — no cost layer, no timestamp update
- [ ] PO detail shows stale badge on line items with outdated pricing
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16G Results (YYYY-MM-DD)
- Service: isPartPriceStale, getStalePricedParts, markPriceVerified
- Receiving flow: 3-option price verification (matches/different/not shown)
- Cost layers created automatically during receiving
- Stale badge on PO detail line items
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16H.**
