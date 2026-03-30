# 62O — Add Delivery Timeline Bars to PO Line Items
> Chain position: Standalone

## Task

Add visual delivery timeline bars to PO line items on `IOSPODetailPage`. The bar shows progress from order date to expected delivery, colored green-to-red based on how close the delivery is.

### Step 1: Create the timeline bar component

Add a reusable view (can be in the same file or a shared components file):

```swift
struct DeliveryTimelineBar: View {
    let orderDate: Date?
    let expectedDelivery: Date?
    let averageDeliveryDays: Int?  // 3-month avg for this supplier

    private var progress: Double {
        guard let start = orderDate else { return 0 }
        let end = expectedDelivery ?? Calendar.current.date(byAdding: .day, value: averageDeliveryDays ?? 14, to: start)!
        let totalDays = max(end.timeIntervalSince(start) / 86400, 1)
        let elapsedDays = Date().timeIntervalSince(start) / 86400
        return min(max(elapsedDays / totalDays, 0), 1.5)  // Allow over 1.0 for overdue
    }

    private var barColor: Color {
        if progress > 1.0 { return .red }       // Overdue
        if progress > 0.8 { return .orange }    // Getting close
        if progress > 0.5 { return .yellow }    // Halfway
        return .green                            // Plenty of time
    }

    private var statusText: String {
        guard let expected = expectedDelivery else {
            if let avg = averageDeliveryDays {
                return "~\(avg) day avg"
            }
            return "No ETA"
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expected).day ?? 0
        if days < 0 { return "\(-days)d overdue" }
        if days == 0 { return "Due today" }
        return "\(days)d remaining"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.gray.opacity(0.2))
                        .frame(height: 6)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 6)

                    // Overdue indicator (red extends past the bar)
                    if progress > 1.0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.red.opacity(0.3))
                            .frame(height: 6)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(progress > 1.0 ? .red : .secondary)
                Spacer()
                if let expected = expectedDelivery {
                    Text(expected, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 2: Add supplier average delivery time to the service

In `OrdersService.swift`, add a method to get average delivery time for a supplier:

```swift
/// Get the average delivery time in days for a supplier (last 3 months).
public func getSupplierAvgDeliveryDays(supplierId: Int64) throws -> Int? {
    do {
        return try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT AVG(
                    CAST(julianday(
                        COALESCE(
                            (SELECT MIN(rs.completed_at) FROM receiving_sessions rs WHERE rs.po_id = po.id),
                            po.updated_at
                        )
                    ) - julianday(po.order_date) AS INTEGER)
                )
                FROM purchase_orders po
                WHERE po.supplier_id = ? AND po.status = 'received'
                  AND po.order_date >= date('now', '-3 months')
                  AND po.deleted_at IS NULL
                """, arguments: [supplierId])
        }
    } catch {
        if isTableNotFoundError(error) { return nil }
        throw error
    }
}
```

### Step 3: Display the timeline bar on each line item

In `IOSPODetailPage.swift`, add the `DeliveryTimelineBar` below each line item row (or in a collapsible detail section):

```swift
// In the line item row, after the existing content:
if poDetail?.status == "ordered" || poDetail?.status == "partial" {
    DeliveryTimelineBar(
        orderDate: parseDate(poDetail?.orderDate),
        expectedDelivery: parseDate(poDetail?.expectedDelivery),
        averageDeliveryDays: supplierAvgDays
    )
    .padding(.top, 4)
}
```

Load the supplier average in `loadData()`:

```swift
@State private var supplierAvgDays: Int?

// In loadData():
if let supplierId = poDetail?.supplierId {
    supplierAvgDays = try? appCore.ordersService?.getSupplierAvgDeliveryDays(supplierId: supplierId)
}
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — add DeliveryTimelineBar component and display it
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add getSupplierAvgDeliveryDays method

## Success Criteria
- [ ] Each PO line item shows a green-to-red timeline bar when PO is ordered/partial
- [ ] Bar shows days remaining or days overdue
- [ ] Overdue items show red bar with "Xd overdue" text
- [ ] When no expected delivery date, bar uses supplier's 3-month average
- [ ] Timeline bar not shown for draft/completed POs
- [ ] No compile errors
