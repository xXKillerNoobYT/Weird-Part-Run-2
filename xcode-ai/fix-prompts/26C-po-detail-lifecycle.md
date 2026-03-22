# 26C — PO Detail: Status-Based Actions + Lifecycle

> **Chain position:** 26A → 26B → **26C** → 26D → 26E → 26F
> **Prerequisite:** 26B complete (swipe actions, sort, KPI)
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Section 9, Status Details table
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The PO detail page currently has only ONE action (Receive Shipment) in a toolbar menu. It needs status-aware action buttons that change based on the PO's lifecycle state. The page also needs a new "Drafting / Unclear Details" status for POs that need clarification from the job creator.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — current implementation
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — search for PO-related methods
- `docs/plans/ios-purchase-orders-page.md` — full design spec

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (add status transition methods if missing)

## Task

### Step 1: Fix status color mismatch

Change `"sent"` to `"submitted"` in the `statusColor` function. Also add `"drafting"` and `"backorder"` statuses:

```swift
private func statusColor(_ status: String) -> Color {
    switch status {
    case "draft": .secondary
    case "submitted": .orange
    case "ordered": .blue
    case "partial": .purple
    case "received": .green
    case "cancelled": .red
    case "drafting": .yellow
    default: .secondary
    }
}
```

### Step 2: Replace toolbar menu with status-based action buttons

Remove the current single-item toolbar Menu. Replace with a VStack of action buttons inside the ScrollView, right below the status badge section. The buttons change based on the current PO status:

```swift
@ViewBuilder
private func actionButtons(for status: String) -> some View {
    VStack(spacing: 8) {
        switch status {
        case "draft":
            HStack(spacing: 8) {
                actionButton("Submit to Supplier", icon: "paperplane.fill", color: .blue) {
                    await transitionPO(to: "submitted")
                }
                actionButton("Delete Draft", icon: "trash", color: .red, role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
            actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                activeSheet = .managesParts
            }

        case "submitted":
            HStack(spacing: 8) {
                actionButton("Mark Ordered", icon: "checkmark.circle.fill", color: .blue) {
                    await transitionPO(to: "ordered")
                }
                actionButton("Drafting / Unclear", icon: "questionmark.circle", color: .yellow) {
                    await transitionPO(to: "drafting")
                }
            }
            HStack(spacing: 8) {
                actionButton("Cancel PO", icon: "xmark.circle", color: .red) {
                    showCancelConfirmation = true
                }
                actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                    activeSheet = .contactSupplier
                }
            }

        case "ordered":
            HStack(spacing: 8) {
                actionButton("Receive Shipment", icon: "shippingbox.and.arrow.backward.fill", color: .green) {
                    activeSheet = .receiveShipment
                }
                actionButton("Update ETA", icon: "calendar.badge.clock", color: .orange) {
                    activeSheet = .updateETA
                }
            }
            HStack(spacing: 8) {
                actionButton("Cancel PO", icon: "xmark.circle", color: .red) {
                    showCancelConfirmation = true
                }
                actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                    activeSheet = .contactSupplier
                }
            }
            actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                activeSheet = .managesParts
            }

        case "partial":
            HStack(spacing: 8) {
                actionButton("Receive More", icon: "shippingbox.and.arrow.backward.fill", color: .green) {
                    activeSheet = .receiveShipment
                }
                actionButton("Cancel Remaining", icon: "xmark.circle", color: .red) {
                    showCancelRemainingConfirmation = true
                }
            }
            HStack(spacing: 8) {
                actionButton("Contact Supplier", icon: "message.fill", color: .green) {
                    activeSheet = .contactSupplier
                }
                actionButton("Double Order", icon: "doc.on.doc", color: .orange) {
                    activeSheet = .doubleOrder
                }
            }
            actionButton("Manage Parts", icon: "list.bullet.rectangle", color: .accentColor) {
                activeSheet = .managesParts
            }

        case "received":
            HStack(spacing: 8) {
                actionButton("Report Issue", icon: "exclamationmark.triangle", color: .orange) {
                    activeSheet = .reportIssue
                }
                actionButton("View History", icon: "clock.arrow.circlepath", color: .secondary) {
                    activeSheet = .receiptHistory
                }
            }

        case "drafting":
            HStack(spacing: 8) {
                actionButton("Resume Draft", icon: "pencil.circle.fill", color: .blue) {
                    await transitionPO(to: "draft")
                }
                actionButton("Contact Job Creator", icon: "person.fill.questionmark", color: .orange) {
                    activeSheet = .contactCreator
                }
            }

        case "cancelled":
            // Read-only — no actions
            EmptyView()

        default:
            EmptyView()
        }
    }
    .padding(.horizontal)
}
```

### Step 3: Add the action button helper

```swift
private func actionButton(_ title: String, icon: String, color: Color, role: ButtonRole? = nil, action: @escaping () async -> Void) -> some View {
    Button(role: role) {
        Task { await action() }
    } label: {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
}
```

### Step 4: Add state for confirmations and sheets

```swift
@State private var activeSheet: ActiveSheet?
@State private var showDeleteConfirmation = false
@State private var showCancelConfirmation = false
@State private var showCancelRemainingConfirmation = false
@State private var cancelReason = ""

private enum ActiveSheet: Identifiable {
    case receiveShipment
    case managesParts
    case contactSupplier
    case updateETA
    case doubleOrder
    case reportIssue
    case receiptHistory
    case contactCreator

    var id: String { String(describing: self) }
}
```

### Step 5: Add transition method

```swift
private func transitionPO(to newStatus: String) async {
    guard let service = appCore.ordersService else { return }
    do {
        try service.updatePOStatus(id: poId, status: newStatus)
        loadData() // Reload to reflect new status + available actions
    } catch {
        actionMessage = "Failed to update status: \(error.localizedDescription)"
    }
}
```

### Step 6: Add confirmation alerts

Replace the current `.alert` with proper confirmation dialogs:

```swift
.alert("Cancel Purchase Order?", isPresented: $showCancelConfirmation) {
    TextField("Reason (required)", text: $cancelReason)
    Button("Keep Order", role: .cancel) { cancelReason = "" }
    Button("Cancel PO", role: .destructive) {
        Task {
            guard !cancelReason.isEmpty else {
                actionMessage = "Cancellation reason is required."
                return
            }
            // TODO: pass cancelReason to service
            await transitionPO(to: "cancelled")
            cancelReason = ""
        }
    }
} message: {
    Text("This will cancel the entire purchase order. A reason is required.")
}
```

Add similar alerts for `showDeleteConfirmation` and `showCancelRemainingConfirmation`.

### Step 7: Add sheet content handler

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .receiveShipment:
        NavigationStack {
            IOSReceiveShipmentPage()
                .environmentObject(appCore)
        }
    case .managesParts:
        // TODO: Parts Management page (prompt 26E)
        Text("Parts Management — Coming Soon")
    case .contactSupplier:
        // TODO: Supplier bridge channel (prompt 26D)
        Text("Supplier Contact — Coming Soon")
    case .updateETA:
        // TODO: ETA update sheet
        Text("Update ETA — Coming Soon")
    case .doubleOrder:
        // TODO: Double order flow
        Text("Double Order — Coming Soon")
    case .reportIssue:
        // TODO: Issue reporting
        Text("Report Issue — Coming Soon")
    case .receiptHistory:
        // TODO: Receipt batch timeline
        Text("Receipt History — Coming Soon")
    case .contactCreator:
        // TODO: Contact job creator
        Text("Contact Creator — Coming Soon")
    }
}
```

### Step 8: Wire action buttons into the content view

In `poContent()`, add the action buttons right after the status/date header:

```swift
// After status HStack:
actionButtons(for: po.status)
```

### Step 9: Verify OrdersService has updatePOStatus

Check if `OrdersService` has an `updatePOStatus(id:status:)` method. If not, add one:

```swift
public func updatePOStatus(id: Int64, status: String) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(
            sql: """
                UPDATE purchase_orders SET status = ?, updated_at = datetime('now')
                WHERE id = ?
                """,
            arguments: [status, id]
        )
    }
}
```

## Important Notes

- The `actionButton` helper creates uniform, tappable buttons with 44px+ height
- "Double Order" is NOT available for generic parts (supplier locked per job) — this will be enforced in the Double Order sheet (prompt 26E), not here
- "Cancel Remaining" requires contacting the supplier first — the confirmation dialog should remind the user
- The `activeSheet` cases with `// TODO` comments will be implemented in subsequent prompts (26D-26F). For now they show placeholder text.
- Keep the existing stale price warning on line items — don't remove it

## Success Criteria

- [ ] Status colors include "submitted" (not "sent"), "drafting"
- [ ] Action buttons change based on PO status (7 status states)
- [ ] Draft: Submit + Delete Draft + Manage Parts
- [ ] Ordered: Receive + Update ETA + Cancel + Contact Supplier + Manage Parts
- [ ] Partial: Receive More + Cancel Remaining + Contact Supplier + Double Order + Manage Parts
- [ ] Cancel confirmation requires reason (not optional)
- [ ] Transition updates status and reloads page
- [ ] Sheet stubs present for all action types
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26C Results (YYYY-MM-DD)
- Status-based action buttons for 7 states
- Transition method + confirmation alerts with required reason
- Sheet stubs for all action types
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 26D.**
