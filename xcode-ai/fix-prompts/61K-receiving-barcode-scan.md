# 61K — Add Per-Item Barcode Scan During Receiving

> **Chain position:** **61K** (standalone)
> **Issue:** T2-13
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT replace existing manual quantity entry — barcode scan is ADDITIONAL
2. The scan button must appear on EACH line item row
3. Use the existing camera/barcode scanning infrastructure (QRScanSheet or similar)
4. Auto-scroll to and highlight the matched item after scan
5. Project must build with zero errors when done

## Context

During receiving (checking in a PO shipment), warehouse workers must manually find each item in a long list and enter the received quantity. With barcode scanning, they can scan an item's barcode and the app automatically finds it in the list, scrolls to it, and highlights it. This dramatically speeds up receiving.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

## Task

### 1. Find Existing Barcode Scanner

Search the project for existing barcode/QR scanning components:
- `QRScanSheet` in `Weird Parts IOS/Weird Parts IOS/Scanning/QRScanSheet.swift`
- `IOSCameraMatchView` in Scanning/
- Any `AVCaptureSession` or `DataScannerViewController` usage

Use whichever scanner already exists. If `QRScanSheet` handles both QR and barcodes, use it. If it's QR-only, create a barcode mode.

### 2. Add Scan Button to Page Header

Add a toolbar button to scan barcodes:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showBarcodeScanner = true
        } label: {
            Label("Scan Item", systemImage: "barcode.viewfinder")
        }
    }
}
```

### 3. Add Per-Item Scan Button

On each line item row, add a small scan button:
```swift
HStack {
    // existing line item content...

    Button {
        scanningForItemId = item.id
        showBarcodeScanner = true
    } label: {
        Image(systemName: "barcode.viewfinder")
            .font(.title3)
    }
    .frame(minWidth: 44, minHeight: 44)
    .buttonStyle(.borderless)
}
```

### 4. Handle Barcode Result

When a barcode is scanned, match it against the PO line items:

```swift
@State private var showBarcodeScanner = false
@State private var highlightedItemId: Int64?
@State private var scanningForItemId: Int64?

.sheet(isPresented: $showBarcodeScanner) {
    QRScanSheet(mode: .barcode) { scannedCode in
        handleScannedBarcode(scannedCode)
        showBarcodeScanner = false
    }
}

func handleScannedBarcode(_ code: String) {
    // Find the line item whose part has this barcode
    if let matchedItem = lineItems.first(where: { $0.partBarcode == code || $0.partSku == code }) {
        // Highlight the matched item
        withAnimation {
            highlightedItemId = matchedItem.id
        }
        // Auto-increment received quantity
        if var qty = receivedQuantities[matchedItem.id] {
            receivedQuantities[matchedItem.id] = qty + 1
        } else {
            receivedQuantities[matchedItem.id] = 1
        }
        // Clear highlight after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                if highlightedItemId == matchedItem.id {
                    highlightedItemId = nil
                }
            }
        }
    } else {
        // No match found
        scanError = "No item found matching barcode: \(code)"
    }
}
```

### 5. Auto-Scroll to Matched Item

Use `ScrollViewReader` to scroll to the matched item:

```swift
ScrollViewReader { proxy in
    List {
        ForEach(lineItems) { item in
            LineItemRow(item: item)
                .id(item.id)
                .background(
                    highlightedItemId == item.id
                        ? Color.green.opacity(0.2)
                        : Color.clear
                )
        }
    }
    .onChange(of: highlightedItemId) { _, newId in
        if let id = newId {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
```

### 6. Highlight Animation

The matched item should flash green briefly:
```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(highlightedItemId == item.id ? Color.green.opacity(0.2) : Color.clear)
        .animation(.easeInOut(duration: 0.3), value: highlightedItemId)
)
```

### 7. Show Scan Count Badge

After scanning, show how many items have been scanned vs total:
```swift
Text("Scanned: \(scannedCount)/\(lineItems.count)")
    .font(.caption)
    .foregroundColor(.secondary)
```

### 8. Handle "No Match" Error

If the scanned barcode doesn't match any line item, show an alert:
```swift
@State private var scanError: String?

.alert("Barcode Not Found", isPresented: .init(
    get: { scanError != nil },
    set: { if !$0 { scanError = nil } }
)) {
    Button("OK") { scanError = nil }
} message: {
    Text(scanError ?? "")
}
```

## Success Criteria

- [ ] Toolbar scan button opens barcode scanner
- [ ] Per-item scan button available on each line item row
- [ ] Scanned barcode matched against PO line items (by barcode or SKU)
- [ ] Matched item auto-scrolled to and highlighted green
- [ ] Received quantity auto-incremented on successful scan
- [ ] "Barcode Not Found" alert shown for unmatched scans
- [ ] Highlight fades after 3 seconds
- [ ] Existing manual quantity entry still works
- [ ] Project builds with zero errors
