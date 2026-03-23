# 33C — JPO Smart Routing: Stock Check Before Approval

> **Chain position:** **33C** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use empty `catch { }` blocks
2. DO NOT use `#if os(iOS)` guards
3. DO NOT use `print()` for errors

## Context

When a JPO line item is approved, the system should check shop stock BEFORE sending to procurement. If the shop has enough stock, create a warehouse transfer movement instead of a purchase order.

**Rules confirmed in design review:**
- If 100% of parts CAN'T be grabbed from shelf → needs approval for ordering
- If grabbing would bring stock below MIN → ask for approval but don't block if transfer already started
- If hold is pressed before transfer starts → remove from transfer list
- Staging parts don't count toward inventory (reserved/sold)

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — approveLine() method
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — may need new method

## Task

### Update approveLine() Logic

When user taps [Approve] on a JPO line item:

```swift
func approveLine(_ line: JPOLineItem) async {
    guard let ordersService = appCore.ordersService,
          let warehouseService = appCore.warehouseService else {
        actionError = "Service not available"
        return
    }

    do {
        // Step 1: Check shop stock for this part
        let shopStock = try warehouseService.getStockAtLocation(
            partId: line.partId,
            locationType: "warehouse",
            locationId: nil  // main shop
        )

        let partTargets = try appCore.partsService?.getLocationStockTarget(
            partId: line.partId,
            locationType: "warehouse",
            locationId: 0  // main shop default
        )

        let minLevel = partTargets?.minStock ?? 0
        let targetLevel = partTargets?.targetStock ?? 0

        if shopStock >= line.quantity {
            // Shop has enough — create transfer to staging
            if shopStock - line.quantity < minLevel {
                // Would go below MIN — ask for approval but allow
                showBelowMinWarning = true
                pendingTransferLine = line
            } else {
                // Safe to transfer — create pending movement
                try ordersService.updateJPOLineStatus(
                    jpoId: line.jpoId,
                    lineId: line.id,
                    status: "transfer"
                )
                // Create pending warehouse movement
                try warehouseService.createPendingMovement(
                    partId: line.partId,
                    quantity: line.quantity,
                    fromType: "warehouse",
                    toType: "staging",
                    reason: "JPO #\(jpoNumber) - \(line.partName)"
                )
            }
        } else {
            // Shop doesn't have enough — send to procurement
            try ordersService.updateJPOLineStatus(
                jpoId: line.jpoId,
                lineId: line.id,
                status: "approved"
            )
        }

        await loadData()
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Add Below-MIN Warning Alert

```swift
@State private var showBelowMinWarning = false
@State private var pendingTransferLine: JPOLineItem?

.alert("Stock Warning", isPresented: $showBelowMinWarning) {
    Button("Transfer Anyway") {
        Task { await executeTransfer(pendingTransferLine) }
    }
    Button("Send to Procurement") {
        Task { await sendToProcurement(pendingTransferLine) }
    }
    Button("Cancel", role: .cancel) { pendingTransferLine = nil }
} message: {
    Text("Pulling this quantity will bring shop stock below minimum level. Transfer anyway or send to procurement for ordering?")
}
```

### Hold Cancels Pending Transfer

If a line is in "transfer" status and manager presses Hold:

```swift
func holdLine(_ line: JPOLineItem) async {
    // If there's a pending transfer, cancel it
    if line.status == "transfer" {
        try? warehouseService.cancelPendingMovement(
            partId: line.partId,
            reason: "JPO line placed on hold"
        )
    }
    try? ordersService.updateJPOLineStatus(
        jpoId: line.jpoId, lineId: line.id, status: "on_hold"
    )
    await loadData()
}
```

## Success Criteria

- [ ] Approve checks shop stock before deciding transfer vs procurement
- [ ] Below-MIN warning shown but doesn't block transfer
- [ ] Hold on a "transfer" status line cancels the pending movement
- [ ] Staging parts not counted in stock check
- [ ] Project builds with no errors
