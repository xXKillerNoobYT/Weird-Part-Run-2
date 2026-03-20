# 20B — QR Scanner Integration: Orders (PO Creation + Procurement)

> **Chain position:** 20A → **20B** → 20C → 20D
> **Prerequisite:** 20A complete (QRScanSheet reusable component exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The `QRScanSheet` reusable component was created in prompt 20A. Now wire it into the Orders module so users can scan QR codes to speed up PO creation and procurement workflows.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/CreatePOSheet.swift` (if it exists as separate file)
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSProcurementPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`

**Reusable component from 20A:**
- `Weird Parts IOS/Weird Parts IOS/Scanning/QRScanSheet.swift`

## Task

### Step 1: Add QR scan to PO creation for adding line items

When creating a PO (in `CreatePOSheet` or wherever PO line items are added), add a "Scan Part" button that scans a part QR code and adds it as a line item.

```swift
// In the line items section of the PO creation form:
Section {
    // Existing line items list...

    // Add scan button at bottom of line items section:
    Button {
        showPartScanner = true
    } label: {
        Label("Scan Part to Add", systemImage: "qrcode.viewfinder")
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
    }
} header: {
    Text("Line Items")
}

@State private var showPartScanner = false

// Add sheet (if this view doesn't already have a sheet, use .sheet(isPresented:)):
.sheet(isPresented: $showPartScanner) {
    QRScanSheet(expectedType: .part) { result in
        if let partId = result.entityId, result.isFound {
            // Add as a new line item with qty=1
            addLineItem(
                partId: partId,
                partName: result.fields["_title"] ?? result.code,
                partCode: result.fields["code"] ?? result.code,
                qty: 1
            )
        }
    }
    .environmentObject(appCore)
}
```

### Step 2: Add supplier scan to PO creation

If the PO creation form has a supplier picker, add a "Scan Supplier" option:

```swift
// Next to the supplier picker:
HStack {
    // Existing supplier picker...
    Spacer()
    Button {
        showSupplierScanner = true
    } label: {
        Image(systemName: "qrcode.viewfinder")
            .frame(width: 44, height: 44)
    }
}

@State private var showSupplierScanner = false

.sheet(isPresented: $showSupplierScanner) {
    QRScanSheet(expectedType: .supplier) { result in
        if let supplierId = result.entityId, result.isFound {
            selectedSupplierId = supplierId
            selectedSupplierName = result.fields["_title"] ?? result.code
        }
    }
    .environmentObject(appCore)
}
```

### Step 3: Add QR scan to Purchase Orders list page

On `IOSPurchaseOrdersPage`, add a toolbar scan button that scans a PO QR code and navigates directly to that PO's detail page.

```swift
// Add to toolbar:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 12) {
            Button {
                showQRScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            // Existing + button for create PO
            Button { showCreatePO = true } label: {
                Image(systemName: "plus")
            }
        }
    }
}

@State private var showQRScanner = false
@State private var scannedPOId: Int64?

.sheet(isPresented: $showQRScanner) {
    QRScanSheet(expectedType: .po) { result in
        if let poId = result.entityId, result.isFound {
            scannedPOId = poId
        }
    }
    .environmentObject(appCore)
}

// Navigate to PO detail when scanned:
.onChange(of: scannedPOId) { _, newId in
    if let poId = newId {
        // Navigate to PO detail — use whatever navigation pattern the page uses
        // Could be NavigationLink, sheet, or router
        selectedPO = purchaseOrders.first(where: { $0.id == poId })
        scannedPOId = nil
    }
}
```

If the page uses an `ActiveSheet` enum, add a `.qrScanner` case instead of a separate `showQRScanner` bool.

### Step 4: Add QR scan to Procurement page

On `IOSProcurementPage`, add a scan button that scans a JPO and auto-selects it for PO generation.

```swift
// Add toolbar button:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showQRScanner = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
        }
    }
}

@State private var showQRScanner = false

.sheet(isPresented: $showQRScanner) {
    // JPOs don't have a dedicated QR type — they're "po" type
    QRScanSheet(expectedType: .po) { result in
        if let poId = result.entityId, result.isFound {
            // Check if this is a JPO and select it
            highlightedJPOId = poId
        }
    }
    .environmentObject(appCore)
}
```

## Important Notes

- If `CreatePOSheet` is defined inline in `IOSPurchaseOrdersPage.swift` (as a private struct), add the scan buttons there.
- If it's a separate file, modify that file instead.
- The scan buttons should be clearly labeled with "qrcode.viewfinder" SF Symbol — this is the standard QR scan icon.
- Multiple `.sheet` modifiers on the same view won't work. If the page already has sheets, integrate QR into the existing `ActiveSheet` enum or use `.sheet(item:)`.
- Auto-fill should ADD a line item, not replace existing ones.

## Success Criteria

- [ ] PO creation form has "Scan Part" button to add line items via QR
- [ ] Supplier can be selected by QR scan in PO creation
- [ ] Purchase Orders list has QR scan button to navigate to specific PO
- [ ] Procurement page has QR scan for JPO selection
- [ ] All scans use `QRScanSheet` from 20A
- [ ] No duplicate `.sheet` conflicts
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 20B Results (YYYY-MM-DD)
- PO creation: scan part to add line item, scan supplier to select
- PO list: scan PO to navigate to detail
- Procurement: scan JPO to select
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 20C.**
