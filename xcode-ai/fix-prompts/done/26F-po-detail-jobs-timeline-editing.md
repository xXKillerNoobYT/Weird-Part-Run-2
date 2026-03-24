# 26F — PO Detail: Job Grouping, Delivery Timeline, Inline Editing, Receipt History

> **Chain position:** 26A → 26B → 26C → 26D → 26E → **26F**
> **Prerequisite:** 26E complete (Parts Order Management page)
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Section 9, Q2-Q4 answers
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding.

## Context

The PO detail page shows line items in a flat list. They need to be grouped by job (Job #412, Job #418, Forecast, Wishlist). Each waiting part needs a delivery timeline bar showing green→red based on lateness. Draft POs need inline qty/price editing. Received POs need a receipt batch timeline.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — current page (after 26C + 26D)
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — POLineRow struct, PODetail struct
- `docs/plans/ios-purchase-orders-page.md` — Section 7 (delivery timeline), Q2-Q4 answers

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (add receipt history method, add job info to lines)

## Task

### Step 1: Add job info to POLineRow

The `POLineRow` struct needs a `jobId` and `jobName` field so lines can be grouped by job. Update the struct:

```swift
// Add to POLineRow:
public let jobId: Int64?
public let jobName: String?
public let source: String?  // "job", "forecast", "wishlist", "auto"
```

Update the `getPODetail` SQL query to JOIN through `jpo_line_id` → `jpo_lines` → `job_purchase_orders` → `jobs` to get the job name:

```sql
SELECT li.*,
       COALESCE(j.job_name,
           CASE WHEN li.notes LIKE '%forecast%' THEN 'Forecast Restock'
                WHEN li.notes LIKE '%wishlist%' THEN 'Wishlist'
                ELSE 'General'
           END
       ) AS job_name,
       j.id AS job_id
FROM po_line_items li
LEFT JOIN jpo_lines jl ON jl.id = li.jpo_line_id
LEFT JOIN job_purchase_orders jpo ON jpo.id = jl.jpo_id
LEFT JOIN jobs j ON j.id = jpo.job_id
WHERE li.po_id = ?
ORDER BY job_name ASC, li.id ASC
```

Check the actual table/column names — they may differ. The key is resolving `jpo_line_id` back to a job name.

### Step 2: Group line items by job in the UI

Replace the flat `ForEach(po.lines)` with grouped sections:

```swift
@ViewBuilder
private func lineItemsSection(_ po: OrdersService.PODetail) -> some View {
    let grouped = Dictionary(grouping: po.lines) { $0.jobName ?? "General" }
    let sortedKeys = grouped.keys.sorted()

    VStack(alignment: .leading, spacing: 12) {
        Text("Line Items (\(po.lines.count))")
            .font(.headline)

        ForEach(sortedKeys, id: \.self) { jobName in
            if let lines = grouped[jobName] {
                VStack(alignment: .leading, spacing: 4) {
                    // Job header
                    HStack {
                        Image(systemName: jobName == "Forecast Restock" ? "chart.line.uptrend.xyaxis" :
                                         jobName == "Wishlist" ? "heart" : "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(jobName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(lines.count) items")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)

                    // Lines for this job
                    ForEach(lines, id: \.id) { line in
                        lineItemRow(line, isDraft: po.status == "draft")
                    }
                }
            }
        }
    }
}
```

### Step 3: Build the line item row with delivery timeline + inline editing

```swift
@ViewBuilder
private func lineItemRow(_ line: OrdersService.POLineRow, isDraft: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            // Status icon
            lineStatusIcon(line.lineStatus)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.partName ?? "Item")
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Stale price warning (keep existing)
                if let partId = line.partId,
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

                HStack(spacing: 8) {
                    Text("Qty: \(line.quantityOrdered)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if line.quantityReceived > 0 {
                        Text("Received: \(line.quantityReceived)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if let price = line.unitPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(price * Double(line.quantityOrdered)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }

        // Delivery timeline bar (for waiting/ordered parts)
        if line.lineStatus == "pending" || line.lineStatus == "ordered" {
            deliveryTimelineBar(orderDate: line.createdAt, expectedDelivery: nil) // Pass actual dates
        }

        // Backorder actions (per line item — confirmed in Q2)
        if line.lineStatus == "backorder" {
            HStack(spacing: 8) {
                Button {
                    // TODO: Update ETA sheet for this specific line
                } label: {
                    Label("Update ETA", systemImage: "calendar.badge.clock")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    // TODO: Double order for this line
                } label: {
                    Label("Double Order", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .padding(.top, 2)
        }

        // Inline editing (for draft POs — confirmed in Q4)
        if isDraft {
            HStack(spacing: 8) {
                Button {
                    editingLineId = line.id
                    editQty = "\(line.quantityOrdered)"
                    editPrice = line.unitPrice.map { String(format: "%.2f", $0) } ?? ""
                    showInlineEdit = true
                } label: {
                    Label("Quick Edit", systemImage: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
            .padding(.top, 2)
        }
    }
    .padding(10)
    .dsCard()
}
```

### Step 4: Build delivery timeline bar

```swift
@ViewBuilder
private func deliveryTimelineBar(orderDate: String?, expectedDelivery: String?) -> some View {
    // Calculate days elapsed and expected
    let daysElapsed = daysSince(orderDate)
    let daysExpected = daysUntil(expectedDelivery) ?? 7 // Default 7 days if no ETA
    let totalDays = max(daysElapsed + max(daysExpected, 0), 1)
    let progress = min(Double(daysElapsed) / Double(totalDays), 1.0)

    // Color based on lateness
    let barColor: Color = {
        if daysExpected > 2 { return .green }       // On track
        if daysExpected > 0 { return .yellow }       // Getting close
        if daysExpected > -2 { return .orange }      // 1-2 days late
        return .red                                   // 3+ days late
    }()

    VStack(alignment: .leading, spacing: 2) {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)

        HStack {
            Text("Day \(daysElapsed)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
            if daysExpected > 0 {
                Text("\(daysExpected)d remaining")
                    .font(.system(size: 9))
                    .foregroundStyle(barColor)
            } else if daysExpected == 0 {
                Text("Due today")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            } else {
                Text("\(-daysExpected)d LATE")
                    .font(.system(size: 9))
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
            }
        }
    }
}

private func daysSince(_ dateStr: String?) -> Int {
    guard let str = dateStr else { return 0 }
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withFullDate]
    guard let date = fmt.date(from: String(str.prefix(10))) else { return 0 }
    return max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
}

private func daysUntil(_ dateStr: String?) -> Int? {
    guard let str = dateStr else { return nil }
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withFullDate]
    guard let date = fmt.date(from: String(str.prefix(10))) else { return nil }
    return Calendar.current.dateComponents([.day], from: Date(), to: date).day
}
```

### Step 5: Build line status icon

```swift
@ViewBuilder
private func lineStatusIcon(_ status: String) -> some View {
    switch status {
    case "received":
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.body)
    case "backorder":
        Image(systemName: "clock.badge.exclamationmark.fill")
            .foregroundStyle(.red)
            .font(.body)
    case "pending", "ordered":
        Image(systemName: "hourglass")
            .foregroundStyle(.blue)
            .font(.body)
    case "cancelled":
        Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.red)
            .font(.body)
    default:
        Image(systemName: "circle")
            .foregroundStyle(.secondary)
            .font(.body)
    }
}
```

### Step 6: Inline edit sheet for Draft POs

```swift
@State private var editingLineId: Int64?
@State private var editQty = ""
@State private var editPrice = ""
@State private var showInlineEdit = false

// Add alert-style inline edit:
.alert("Edit Line Item", isPresented: $showInlineEdit) {
    TextField("Quantity", text: $editQty)
        .keyboardType(.numberPad)
    TextField("Unit Price", text: $editPrice)
        .keyboardType(.decimalPad)
    Button("Cancel", role: .cancel) { }
    Button("Save") {
        Task { await saveLineEdit() }
    }
} message: {
    Text("Update quantity and unit price for this item.")
}
```

Add the save method:

```swift
private func saveLineEdit() async {
    guard let lineId = editingLineId,
          let qty = Int(editQty), qty > 0,
          let service = appCore.ordersService else { return }
    let price = Double(editPrice)
    do {
        try service.updatePOLineItem(lineId: lineId, quantity: qty, unitPrice: price)
        loadData()
    } catch {
        actionMessage = "Failed to update: \(error.localizedDescription)"
    }
}
```

### Step 7: Add receipt history (for Received status — confirmed in Q3)

Add a service method for receipt batches:

```swift
// In OrdersService:
public struct ReceiptBatch: Sendable, Identifiable {
    public let id: Int64
    public let receivedDate: String
    public let receivedBy: String?
    public let itemCount: Int
    public let items: [ReceiptBatchItem]
}

public struct ReceiptBatchItem: Sendable {
    public let partName: String
    public let quantityReceived: Int
    public let priceVerified: Bool
}

public func getReceiptHistory(poId: Int64) throws -> [ReceiptBatch] {
    // Query receiving_sessions or order_status_history for batch-by-batch info
    // Return grouped by session/date
    // TODO: adapt to actual table structure
    return []
}
```

In the UI, add a receipt timeline section that shows when status is "received":

```swift
if po.status == "received" || po.status == "partial" {
    VStack(alignment: .leading, spacing: 8) {
        Text("Receipt History")
            .font(.headline)

        ForEach(receiptBatches) { batch in
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch received \(batch.receivedDate)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(batch.itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let by = batch.receivedBy {
                        Text("By: \(by)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    .padding()
    .dsCard()
}
```

### Step 8: Add updatePOLineItem service method

```swift
// In OrdersService, add if not present:
public func updatePOLineItem(lineId: Int64, quantity: Int, unitPrice: Double?) throws {
    try db.writer.write { dbConn in
        var setClauses = ["quantity_ordered = ?", "updated_at = datetime('now')"]
        var args: [DatabaseValueConvertible?] = [quantity]
        if let price = unitPrice {
            setClauses.append("unit_price = ?")
            args.append(price)
        }
        args.append(lineId)
        try dbConn.execute(
            sql: "UPDATE po_line_items SET \(setClauses.joined(separator: ", ")) WHERE id = ?",
            arguments: StatementArguments(args)
        )
    }
}
```

### Step 9: Wire everything into poContent

Replace the existing line items section with `lineItemsSection(po)` and add the receipt history section after the cost summary.

## Important Notes

- Job grouping resolves through: `po_line_items.jpo_line_id` → `jpo_lines.jpo_id` → `job_purchase_orders.job_id` → `jobs.job_name`. Check the actual FK chain.
- Lines without a job link (forecast/wishlist items) get grouped under "Forecast Restock" or "Wishlist" based on notes field content.
- Delivery timeline uses green→red based on days remaining after adjusted ETA — for now we use the simple expected_delivery date. The 3-month-average smart adjustment comes in a future prompt.
- Inline editing is ONLY available on Draft POs. Other statuses show parts as read-only.
- Backorder actions (Update ETA, Double Order) appear PER LINE ITEM as confirmed in Q2.
- Receipt history is a stub — adapt the query to match your actual receiving_sessions or receiving_log tables.
- The `updatePOLineItem` method only works for draft POs — add a status check guard.

## Success Criteria

- [ ] Line items grouped by job name (Job #412, Forecast Restock, etc.)
- [ ] Job headers with icon + name + item count
- [ ] Each waiting line has a green→red delivery timeline bar
- [ ] Backorder lines show [Update ETA] [Double Order] per-item
- [ ] Draft POs show [Quick Edit] button on each line
- [ ] Inline edit alert allows changing qty and price
- [ ] Receipt history timeline shows batch-by-batch for received/partial POs
- [ ] Status icons on each line (✅⏳🔴⚠️)
- [ ] Service method for updating line items exists
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26F Results (YYYY-MM-DD)
- Job-grouped line items with source headers
- Delivery timeline bars (green→red)
- Per-line backorder actions
- Draft inline editing (qty + price)
- Receipt batch history timeline
- Build: [PASS/FAIL]
```

**PO Detail page complete. Continue to next Orders page review.**
