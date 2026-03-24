# 26B — PO List: Swipe Actions + Sort + Awaiting KPI

> **Chain position:** 26A → **26B** → 26C → 26D → 26E → 26F
> **Prerequisite:** 26A complete (cleanup, count badges)
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Sections 2, 3, 4
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The PO list page needs three enhancements: (1) a summary KPI line showing awaiting delivery count, (2) swipe-to-cancel/delete with AI-generated summary confirmation, (3) sort options.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift` — the page (after 26A)
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — PO methods
- `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` — AI summary generation

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (add cancel/delete methods if missing)

## Task

### Step 1: Add awaiting delivery KPI

Add a compact summary line between the status chips and the list:

```swift
private var awaitingCount: Int {
    allPurchaseOrders.filter { $0.status == "ordered" || $0.status == "partial" }.count
}

private var pendingTotal: Double {
    allPurchaseOrders
        .filter { $0.status == "ordered" || $0.status == "partial" || $0.status == "draft" || $0.status == "submitted" }
        .compactMap(\.totalCost)
        .reduce(0, +)
}

// In body, between statusPicker and poList:
if awaitingCount > 0 || pendingTotal > 0 {
    HStack {
        if awaitingCount > 0 {
            Label("\(awaitingCount) awaiting delivery", systemImage: "shippingbox")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        if pendingTotal > 0 {
            Text(formatCurrency(pendingTotal) + " pending")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
}
```

### Step 2: Add sort options

```swift
@State private var sortOption: SortOption = .newest

private enum SortOption: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case totalHigh = "Total (High)"
    case totalLow = "Total (Low)"
    case supplierAZ = "Supplier A-Z"
    case status = "By Status"
}
```

Add a sort menu to the toolbar (alongside the existing QR + Create buttons):

```swift
ToolbarItem(placement: .secondaryAction) {
    Menu {
        ForEach(SortOption.allCases, id: \.self) { option in
            Button {
                sortOption = option
            } label: {
                HStack {
                    Text(option.rawValue)
                    if sortOption == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    } label: {
        Label("Sort", systemImage: "arrow.up.arrow.down")
    }
}
```

Apply sorting to the filtered list:

```swift
private var sortedPOs: [OrdersService.POListItem] {
    let filtered = filteredPOs
    switch sortOption {
    case .newest:
        return filtered.sorted { ($0.orderDate ?? "") > ($1.orderDate ?? "") }
    case .oldest:
        return filtered.sorted { ($0.orderDate ?? "") < ($1.orderDate ?? "") }
    case .totalHigh:
        return filtered.sorted { ($0.totalCost ?? 0) > ($1.totalCost ?? 0) }
    case .totalLow:
        return filtered.sorted { ($0.totalCost ?? 0) < ($1.totalCost ?? 0) }
    case .supplierAZ:
        return filtered.sorted { $0.supplierName < $1.supplierName }
    case .status:
        let order = ["draft": 0, "submitted": 1, "ordered": 2, "partial": 3, "received": 4, "cancelled": 5]
        return filtered.sorted { (order[$0.status] ?? 99) < (order[$1.status] ?? 99) }
    }
}
```

Use `sortedPOs` instead of `filteredPOs` in the List.

### Step 3: Add swipe-to-cancel/delete with AI summary

Add swipe actions to each PO row:

```swift
@State private var poToCancel: OrdersService.POListItem?
@State private var cancelReason = ""
@State private var aiSummary = ""
@State private var showCancelConfirm = false
@State private var isGeneratingSummary = false

// In the List ForEach:
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    if po.status == "draft" {
        Button(role: .destructive) {
            poToCancel = po
            Task { await generateAISummary(for: po) }
            showCancelConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    } else if po.status != "received" && po.status != "cancelled" {
        Button(role: .destructive) {
            poToCancel = po
            Task { await generateAISummary(for: po) }
            showCancelConfirm = true
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
    }
}
```

Add the AI summary generation:

```swift
private func generateAISummary(for po: OrdersService.POListItem) async {
    isGeneratingSummary = true
    let aiService = FoundationModelsService()
    let prompt = """
        Summarize this purchase order in 1-2 sentences for a confirmation dialog:
        PO Number: \(po.poNumber)
        Supplier: \(po.supplierName)
        Status: \(po.status)
        Items: \(po.lineCount) line items
        Total: \(po.totalCost.map { String(format: "$%.2f", $0) } ?? "N/A")
        Ordered: \(po.orderDate ?? "N/A")
        """
    let result = await aiService.generate(instructions: "You summarize purchase orders concisely.", prompt: prompt)
    await MainActor.run {
        aiSummary = result.text ?? "\(po.poNumber): \(po.lineCount) items from \(po.supplierName). Total: \(po.totalCost.map { String(format: "$%.2f", $0) } ?? "N/A")."
        isGeneratingSummary = false
    }
}
```

**Note:** Check if `FoundationModelsService.generate` is public. If not, use `chatWithTools` or build a fallback summary string.

Add the confirmation alert:

```swift
.alert(poToCancel?.status == "draft" ? "Delete Draft?" : "Cancel PO?", isPresented: $showCancelConfirm) {
    TextField("Reason (required)", text: $cancelReason)
    Button("Keep", role: .cancel) {
        cancelReason = ""
        aiSummary = ""
    }
    Button(poToCancel?.status == "draft" ? "Delete" : "Cancel PO", role: .destructive) {
        guard !cancelReason.trimmingCharacters(in: .whitespaces).isEmpty else {
            actionMessage = "Reason is required."
            return
        }
        Task {
            if let po = poToCancel {
                await cancelOrDeletePO(po)
            }
            cancelReason = ""
            aiSummary = ""
        }
    }
} message: {
    if isGeneratingSummary {
        Text("Generating summary...")
    } else {
        Text(aiSummary)
    }
}
```

Add the cancel/delete action:

```swift
private func cancelOrDeletePO(_ po: OrdersService.POListItem) async {
    guard let service = appCore.ordersService else { return }
    do {
        if po.status == "draft" {
            try service.deletePO(id: po.id)
        } else {
            try service.updatePOStatus(id: po.id, status: "cancelled")
            // TODO: store cancelReason
        }
        loadData()
    } catch {
        actionMessage = "Failed: \(error.localizedDescription)"
    }
}
```

Check if `deletePO` and `updatePOStatus` exist in OrdersService. Add them if missing:

```swift
public func deletePO(id: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(
            sql: "UPDATE purchase_orders SET deleted_at = datetime('now') WHERE id = ? AND status = 'draft'",
            arguments: [id]
        )
    }
}
```

## Important Notes

- Swipe-to-delete only appears on Draft POs. All other non-terminal statuses show swipe-to-cancel.
- Received and Cancelled POs have NO swipe action (they're historical).
- AI summary generates asynchronously — show "Generating summary..." while loading, fallback to a formatted string if AI is unavailable.
- Cancel reason is ALWAYS required — the alert blocks submission if empty.
- The `generate` method on FoundationModelsService may be private — check and use whatever public method is available for simple text generation. If none, build the summary string manually from the PO fields.

## Success Criteria

- [ ] Awaiting delivery KPI line shows count + pending $ total
- [ ] Sort menu in toolbar with 6 options
- [ ] Swipe-to-delete on Draft POs
- [ ] Swipe-to-cancel on Submitted/Ordered/Partial POs
- [ ] No swipe on Received/Cancelled POs
- [ ] AI-generated summary in confirmation dialog (with fallback)
- [ ] Cancel reason required — can't submit empty
- [ ] Sort applies correctly to the displayed list
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26B Results (YYYY-MM-DD)
- Awaiting delivery KPI line
- 6 sort options in toolbar menu
- Swipe actions with AI summary confirmation
- Cancel reason enforcement
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 26C.**
