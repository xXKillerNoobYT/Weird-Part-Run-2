# 27C — JPO Detail: Per-Part Actions + Delivery Options + PO Linkage

> **Chain position:** 27A → 27B → **27C** → 27D → 27E
> **Prerequisite:** 27B complete (per-part status model, smart routing)
> **Plan:** `docs/plans/ios-jpo-page.md` — Detail Redesign section
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The JPO detail page currently has JPO-level Approve/Reject buttons and a flat line item list. It needs per-part action buttons (Approve/Hold/Reject), bulk selection with checkboxes, delivery option picker, PO linkage display with delivery timeline bars, and the ActiveSheet pattern. Reject must require a reason.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — current detail (331 lines)
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — JPODetail, JPOLineRow (after 27B updates)
- `docs/plans/ios-jpo-page.md` — full design spec

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift`

## Task

### Step 1: Replace `.sheet(isPresented:)` with ActiveSheet

```swift
@State private var activeSheet: ActiveSheet?

private enum ActiveSheet: Identifiable {
    case addLineItem
    case viewChat(Int64)  // chat thread ID
    case viewPO(Int64)    // PO ID
    case viewMovement(Int64) // movement/transfer ID

    var id: String { String(describing: self) }
}
```

Replace the existing `.sheet(isPresented: $showAddLineItem)` with `.sheet(item: $activeSheet)`.

### Step 2: Remove `#if os(iOS)` platform guards

Remove all 3 platform guard blocks. Keep the iOS code.

### Step 3: Fix guard failures

```swift
guard let service = appCore.ordersService else {
    loadError = "Orders service not available"
    isLoading = false
    return
}
```

### Step 4: Add selection state

```swift
@State private var selectedLineIds: Set<Int64> = []
@State private var rejectReason = ""
@State private var showRejectConfirm = false
@State private var rejectingLineId: Int64?
```

### Step 5: Redesign line items with per-part actions

Replace the existing flat line items section with per-part action rows:

```swift
@ViewBuilder
private func lineItemRow(_ line: OrdersService.JPOLineRow) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 10) {
            // Checkbox for bulk selection
            Button {
                if selectedLineIds.contains(line.id) {
                    selectedLineIds.remove(line.id)
                } else {
                    selectedLineIds.insert(line.id)
                }
            } label: {
                Image(systemName: selectedLineIds.contains(line.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedLineIds.contains(line.id) ? .accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Status icon
            lineStatusIcon(line.lineStatus)

            // Part info
            VStack(alignment: .leading, spacing: 2) {
                Text(line.partName ?? "Unknown Part")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Qty: \(line.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Price
            if let price = line.unitPrice {
                Text(formatCurrency(price * Double(line.quantity)))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }

        // Status-specific content
        switch line.lineStatus {
        case "pending":
            HStack(spacing: 8) {
                Button { approveLine(line.id) } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button { holdLine(line.id) } label: {
                    Label("Hold", systemImage: "pause.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)

                Button {
                    rejectingLineId = line.id
                    showRejectConfirm = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

        case "transfer":
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                Text("In stock — transfer request created")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

        case "on_hold":
            VStack(alignment: .leading, spacing: 4) {
                if let reason = line.holdReason {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.yellow)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    if let threadId = line.chatThreadId {
                        Button { activeSheet = .viewChat(threadId) } label: {
                            Label("View Chat", systemImage: "message.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button { approveLine(line.id) } label: {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button {
                        rejectingLineId = line.id
                        showRejectConfirm = true
                    } label: {
                        Label("Reject", systemImage: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

        case "rejected":
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Rejected: \(line.rejectReason ?? "No reason")")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        case "ordered":
            if let poLineId = line.poLineId {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.blue)
                    Text("Ordered")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("View PO") {
                        // TODO: resolve poLineId → poId
                        // activeSheet = .viewPO(poId)
                    }
                    .font(.caption2)
                }
                // Mini delivery timeline bar
                // deliveryTimelineBar(...)
            }

        case "received":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Received at shop")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        case "delivered":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Delivered to job")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        default:
            EmptyView()
        }
    }
    .padding(10)
    .dsCard()
}
```

### Step 6: Add line status icon helper

```swift
@ViewBuilder
private func lineStatusIcon(_ status: String) -> some View {
    switch status {
    case "pending": Image(systemName: "clock").foregroundStyle(.orange)
    case "approved": Image(systemName: "checkmark.circle").foregroundStyle(.green)
    case "on_hold": Image(systemName: "pause.circle.fill").foregroundStyle(.yellow)
    case "rejected": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
    case "transfer": Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
    case "ordered": Image(systemName: "shippingbox").foregroundStyle(.blue)
    case "received": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case "backorder": Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.red)
    case "delivered": Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
    default: Image(systemName: "circle").foregroundStyle(.secondary)
    }
}
```

### Step 7: Replace JPO-level approve/reject with bulk actions

Remove the existing `if jpo.status == "pending"` approve/reject buttons. Add a bulk action bar:

```swift
if !selectedLineIds.isEmpty {
    VStack(spacing: 0) {
        Divider()
        HStack(spacing: 12) {
            Text("\(selectedLineIds.count) selected")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Button { approveSelected() } label: {
                Label("Approve", systemImage: "checkmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button { holdSelected() } label: {
                Label("Hold + Ask", systemImage: "questionmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.yellow)

            Button {
                showRejectConfirm = true
                rejectingLineId = nil // nil means "reject selected"
            } label: {
                Label("Reject", systemImage: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
```

### Step 8: Add delivery options picker

In the JPO header section, add the delivery option:

```swift
if let jpo = jpo {
    Section("Delivery") {
        let isLocked = jpo.deliveryLocked
        Picker("Delivery Option", selection: Binding(
            get: { jpo.deliveryOption ?? "partial" },
            set: { newValue in updateDeliveryOption(newValue) }
        )) {
            Text("Deliver as parts arrive").tag("partial")
            Text("Wait for complete order").tag("full")
        }
        .disabled(isLocked)
        if isLocked {
            Text("Locked — parts already delivered")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

**Note:** `deliveryOption` and `deliveryLocked` need to be added to `JPODetail` struct.

### Step 9: Add reject confirmation with required reason

```swift
.alert("Reject Part?", isPresented: $showRejectConfirm) {
    TextField("Reason (required)", text: $rejectReason)
    Button("Cancel", role: .cancel) { rejectReason = "" }
    Button("Reject", role: .destructive) {
        guard !rejectReason.trimmingCharacters(in: .whitespaces).isEmpty else {
            actionError = "Rejection reason is required."
            return
        }
        if let lineId = rejectingLineId {
            rejectLine(lineId, reason: rejectReason)
        } else {
            rejectSelected(reason: rejectReason)
        }
        rejectReason = ""
    }
} message: {
    Text("A reason is required for rejection. The requester will be notified.")
}
```

### Step 10: Add action methods

```swift
private func approveLine(_ lineId: Int64) {
    guard let service = appCore.ordersService else { return }
    do {
        try service.updateJPOLineStatus(lineId: lineId, status: "approved")
        loadData()
    } catch { actionError = error.localizedDescription }
}

private func holdLine(_ lineId: Int64) {
    guard let service = appCore.ordersService else { return }
    do {
        try service.updateJPOLineStatus(lineId: lineId, status: "on_hold", reason: "Question pending")
        loadData()
        // TODO: open chat thread (prompt 27D)
    } catch { actionError = error.localizedDescription }
}

private func rejectLine(_ lineId: Int64, reason: String) {
    guard let service = appCore.ordersService else { return }
    do {
        try service.updateJPOLineStatus(lineId: lineId, status: "rejected", reason: reason)
        loadData()
    } catch { actionError = error.localizedDescription }
}

private func approveSelected() {
    for lineId in selectedLineIds { approveLine(lineId) }
    selectedLineIds.removeAll()
}

private func holdSelected() {
    for lineId in selectedLineIds { holdLine(lineId) }
    selectedLineIds.removeAll()
}

private func rejectSelected(reason: String) {
    for lineId in selectedLineIds { rejectLine(lineId, reason: reason) }
    selectedLineIds.removeAll()
}

private func updateDeliveryOption(_ option: String) {
    guard let service = appCore.ordersService else { return }
    do {
        try service.updateJPODeliveryOption(jpoId: jpoId, option: option)
        loadData()
    } catch { actionError = error.localizedDescription }
}
```

### Step 11: Add summary section

Replace the static info fields with a dynamic summary:

```swift
// After line items:
VStack(alignment: .leading, spacing: 4) {
    let statuses = jpo.lines.map(\.lineStatus)
    let pending = statuses.filter { $0 == "pending" }.count
    let approved = statuses.filter { $0 == "approved" || $0 == "in_procurement" }.count
    let transfers = statuses.filter { $0 == "transfer" }.count
    let held = statuses.filter { $0 == "on_hold" }.count

    HStack {
        if transfers > 0 { Label("\(transfers) transfer", systemImage: "arrow.right.circle").font(.caption2).foregroundStyle(.blue) }
        if pending > 0 { Label("\(pending) pending", systemImage: "clock").font(.caption2).foregroundStyle(.orange) }
        if held > 0 { Label("\(held) on hold", systemImage: "pause.circle").font(.caption2).foregroundStyle(.yellow) }
        if approved > 0 { Label("\(approved) approved", systemImage: "checkmark.circle").font(.caption2).foregroundStyle(.green) }
    }
}
```

## Important Notes

- JPO-level Approve/Reject buttons are REMOVED. All actions are now per-part or bulk.
- Reject ALWAYS requires a reason — the alert blocks submission if reason is empty.
- The `deliveryOption` picker is disabled once `deliveryLocked` is true.
- Hold opens a chat thread (wired in prompt 27D). For now, just set status to "on_hold".
- PO linkage display (the timeline bars showing ordered/received/delivered) needs the `po_line_id` from 27B. For now, show "Ordered" text if `poLineId` is set.
- Check actual property names on JPODetail — `deliveryOption` and `deliveryLocked` need to be added to the struct and SQL query.
- Add `updateJPODeliveryOption` to OrdersService if it doesn't exist.

## Success Criteria

- [ ] ActiveSheet pattern replaces `.sheet(isPresented:)`
- [ ] Platform guards removed (3 locations)
- [ ] Per-part Approve/Hold/Reject buttons on each pending line
- [ ] Bulk selection with checkboxes + action bar
- [ ] Reject requires reason (alert enforced)
- [ ] Delivery option picker (locked after delivery)
- [ ] Transfer lines show "In stock — transfer request created"
- [ ] Ordered lines show PO link
- [ ] Status icon for each line
- [ ] Summary showing count by status
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 27C Results (YYYY-MM-DD)
- Per-part actions: Approve/Hold/Reject with checkboxes
- Bulk actions bar
- Delivery option picker (lockable)
- Status-specific content per line
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 27D.**
