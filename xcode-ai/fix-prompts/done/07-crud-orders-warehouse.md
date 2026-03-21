# Fix Prompt 07: Missing CRUD — Orders & Warehouse

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

A user creates a Job Purchase Order (JPO) but can't add line items to it from the detail page. They receive a shipment but can't actually mark items as received. They want to start a warehouse audit but there's no "Start" button. The procurement page shows approved JPOs but has no way to generate a Purchase Order from them.

---

## Files To Fix

### 1. IOSJPODetailPage.swift — Add "Add Line Item" Button

The JPO detail page shows order details but has no way to add parts to the order. Add:

```swift
// Toolbar button
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showAddLineItem = true
        } label: {
            Label("Add Item", systemImage: "plus")
        }
    }
}

// Sheet for adding a line item
.sheet(isPresented: $showAddLineItem) {
    AddJPOLineItemSheet(jpoId: jpoId, onSave: { loadData() })
}
```

The form needs: Part picker (search by name/SKU), Quantity, Notes.
Save calls `appCore.ordersService?.addJPOLineItem(jpoId:partId:quantity:notes:)`.

Also add **Approve** and **Reject** buttons if the JPO is in "pending" status:
```swift
if jpo.status == "pending" {
    HStack {
        Button("Reject") { rejectJPO() }
            .buttonStyle(.bordered)
            .tint(.red)
        Button("Approve") { approveJPO() }
            .buttonStyle(.borderedProminent)
    }
}
```

### 2. IOSPurchaseOrdersPage.swift — Add "Create PO" Button

Add toolbar button to create a new PO manually:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showCreatePO = true } label: { Image(systemName: "plus") }
    }
}
```

### 3. IOSPODetailPage.swift — Add Receive and Export Actions

The PO detail shows info but has no action buttons. Add:
- **"Receive Shipment"** button → navigates to `IOSReceiveShipmentPage` with this PO
- **"Export PDF"** button → generates and shares a PDF of the PO
- **Status badge** showing current PO status

### 4. IOSProcurementPage.swift — Add "Generate PO" Action

This page shows approved JPOs that need to become Purchase Orders. Add a button on each approved JPO row:
```swift
Button("Generate PO") {
    generatePO(fromJPO: jpo)
}

func generatePO(fromJPO jpo: OrdersService.JPOListItem) {
    guard let service = appCore.ordersService else { return }
    do {
        let poId = try service.generatePOFromJPO(jpoId: jpo.id)
        // Show success, navigate to PO detail
    } catch {
        actionError = error.localizedDescription
    }
}
```

### 5. IOSReceiveShipmentPage.swift — Wire Up Receiving Workflow

This page should let users check off items as they arrive. If it currently just navigates to a read-only PO detail, update it to:
- Show each PO line item with a quantity stepper
- "Mark Received" button per item
- "Complete Session" button when all items checked

### 6. IOSReturnsPage.swift — Add "Create Return" Button

Users need to initiate returns. Add:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showCreateReturn = true } label: { Image(systemName: "plus") }
    }
}
```

### 7. IOSAuditPage.swift — Add "Start Audit" Button

The audit page has an audit setup view but the "Start" button may be a stub. Make sure:
- User can select which warehouse zone to audit
- "Start Audit" creates an audit session and navigates to the counting view
- Each bin/location shows expected vs actual count
- "Complete Audit" submits discrepancies

### 8. IOSStagingPage.swift — Add Pull/Stage Actions

Users need to:
- See items staged for pickup
- Mark items as "Pulled" (moved from shelf to staging area)
- Mark items as "Loaded" (put on truck)

### 9. IOSApprovalsPage.swift — Add Approve/Deny Buttons

If the approvals page is read-only, add action buttons:
```swift
HStack {
    Button("Deny") { denyOrder(id: order.id) }
        .buttonStyle(.bordered)
        .tint(.red)
    Button("Approve") { approveOrder(id: order.id) }
        .buttonStyle(.borderedProminent)
}
```

---

## Service Methods You May Need

Check `core/Sources/WiredPartCore/Services/OrdersService.swift` for:
- `addJPOLineItem(jpoId:partId:quantity:notes:)`
- `approveJPO(jpoId:)`, `rejectJPO(jpoId:)`
- `generatePOFromJPO(jpoId:)`
- `createReturn(...)`
- `createAuditSession(...)`

If missing, create stubs that throw a descriptive error. The UI buttons must exist even if the backend isn't complete.

---

## Testing Checklist

1. Open a JPO → can add line items → items show in the detail
2. Open a JPO in "pending" → can Approve or Reject → status changes
3. Procurement page → "Generate PO" button on approved JPOs → creates a PO
4. Warehouse → Audit → "Start Audit" → can count items
5. Approvals page → each pending item has Approve/Deny buttons

---

## When Done

Start **prompt 08 (Missing CRUD — Scheduling & Chat)** next.
