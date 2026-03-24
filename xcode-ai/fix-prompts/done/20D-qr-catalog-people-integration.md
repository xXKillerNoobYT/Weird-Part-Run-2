# 20D — QR Scanner Integration: Parts Catalog + People Directory

> **Chain position:** 20A → 20B → 20C → **20D**
> **Prerequisite:** 20A complete (QRScanSheet reusable component exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Wire QR scanning into the Parts Catalog for quick part lookup and into the People pages for employee badge scanning. These are the final per-module QR integrations.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift`

**Reusable component from 20A:**
- `Weird Parts IOS/Weird Parts IOS/Scanning/QRScanSheet.swift`

## Task

### Step 1: Add QR scan to Parts Catalog

Add a QR scan button to the catalog page toolbar. Scanning a part QR code navigates to that part's detail and applies the correct filters.

```swift
// Add state:
@State private var showPartScanner = false

// Add scan button to toolbar (alongside existing buttons):
// Look for the existing toolbar and add a QR button:
Button {
    showPartScanner = true
} label: {
    Image(systemName: "qrcode.viewfinder")
}

// Add scanner sheet. If the page uses an ActiveSheet enum, add:
case qrScanner

// In the .sheet handler:
case .qrScanner:
    QRScanSheet(expectedType: .part) { result in
        if let partId = result.entityId, result.isFound {
            // Navigate to part detail
            // Option A: If catalog has a part detail sheet, show it:
            selectedPartId = partId
            activeSheet = .partDetail  // or whatever the detail case is

            // Option B: If catalog uses search, set the search text:
            // searchText = result.code
        }
    }
    .environmentObject(appCore)
```

**Alternative approach:** If the catalog page is very large (60KB+) and has complex sheet management, a simpler integration is to set the search text to the scanned code:

```swift
// After scan:
searchText = result.code  // This filters the catalog to show just the scanned part
```

This is simpler and works even if the part detail sheet has complex setup.

### Step 2: Add barcode scan to catalog

Parts often have manufacturer barcodes (UPC, EAN) printed on boxes. The scanner already supports these formats. When a non-WiredPart barcode is scanned, `QRAutoFillService` searches by code/SKU/barcode fields. Make sure the result navigates properly:

```swift
// Using QRScanSheet with expectedType: nil accepts any barcode type
QRScanSheet(expectedType: nil) { result in
    if result.isFound, result.entityType == .part, let partId = result.entityId {
        // Found a matching part
        selectedPartId = partId
    } else if !result.isFound {
        // External barcode — search catalog by the raw code
        searchText = result.code
    }
}
```

Using `expectedType: nil` instead of `.part` lets the scanner accept manufacturer barcodes that don't have a WiredPart QR envelope.

### Step 3: Add QR scan to Employees page

Add a badge scan button to the employees list. Scanning an employee badge/QR code navigates to their detail.

```swift
// In IOSEmployeesPage, add state:
@State private var showBadgeScanner = false

// Add toolbar button (alongside existing + button):
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 12) {
            Button {
                showBadgeScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            // Existing add employee button
            Button { showAddEmployee = true } label: {
                Image(systemName: "plus")
            }
        }
    }
}

// Add scanner sheet:
.sheet(isPresented: $showBadgeScanner) {
    QRScanSheet(expectedType: .employee) { result in
        if let employeeId = result.entityId, result.isFound {
            // Navigate to employee detail
            // Use whatever detail pattern the page uses
            selectedEmployeeId = employeeId
        }
    }
    .environmentObject(appCore)
}
```

If the page uses an `ActiveSheet` enum, add `.badgeScanner` case instead of a separate bool.

### Step 4: Verify QRScanSheet handles external barcodes

Check that `QRScanSheet` from 20A gracefully handles non-WiredPart barcodes:
- Manufacturer UPC/EAN barcodes should search parts by code
- Unknown codes should show the raw code with "Not found" message
- The scanner shouldn't crash or hang on unexpected input

If `QRAutoFillService.processQRScan()` already handles external codes (check `QRScannerAdapter.swift` — it has a `.external` source case), no changes needed. Just verify it works.

## Important Notes

- The Parts Catalog page may be very large. Read it first to understand the existing toolbar, sheet management, and navigation patterns before adding QR.
- Manufacturer barcodes are valuable on the catalog page — warehouse workers scan product packaging constantly.
- Employee badge scanning is lower priority but useful for admin tasks (quickly pulling up someone's record).
- All scan buttons use the `qrcode.viewfinder` SF Symbol for consistency.
- If any page already has multiple `.sheet` modifiers, consolidate into a single `ActiveSheet` enum before adding QR.

## Success Criteria

- [ ] Catalog page has QR/barcode scan button in toolbar
- [ ] Scanning a WiredPart part QR navigates to part detail
- [ ] Scanning a manufacturer barcode searches catalog by code
- [ ] Employees page has badge scan button
- [ ] Scanning an employee badge navigates to employee detail
- [ ] External barcodes handled gracefully (search, not crash)
- [ ] No `.sheet` conflicts on any page
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 20D Results (YYYY-MM-DD)
- Catalog: QR + barcode scan for part lookup (supports manufacturer barcodes)
- Employees: badge scan for quick employee lookup
- External barcodes handled via catalog search fallback
- Build: [PASS/FAIL]
```

**QR per-module integration complete. Continue with the next prompt chain.**
