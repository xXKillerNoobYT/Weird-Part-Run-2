# 29D — Orders Cleanup: Remove UnifiedOrder + Router Update + SupplierPicker

> **Chain position:** After 30E (JPO Creation replaces UnifiedOrder)
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 3
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read all files first, then make changes. When done, wait for user confirmation.

## Context

The `IOSUnifiedOrderPage` is replaced by the JPO Creation page (30A-E). The `OrdersRouter` needs updating for the new tab order. The `SupplierPickerSheet` has a force-unwrap bug and will be superseded by the procurement planner's per-part supplier selection.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — update tab order
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/SupplierPickerSheet.swift` — fix force-unwrap
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — update routes

**Files to remove/redirect:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSUnifiedOrderPage.swift` — replaced by JPO creation flow

## Task

### Step 1: Update OrdersRouter tab order

The Orders section tabs should follow workflow order (process start at top, problem solving at bottom):

```swift
// New tab order:
case "jpos":           IOSJPOsPage()              // 1. Field creates request
case "procurement":    IOSProcurementPage()        // 2. Office sorts into POs
case "purchase-orders": IOSPurchaseOrdersPage()    // 3. POs sent to suppliers
case "parts-mgmt":     IOSPartsOrderManagementPage() // 4. Track across POs
case "stage-planner":  IOSOrderStagingPage()       // 5. Job stage planning
case "approvals":      IOSApprovalsPage()          // 6. Quick approval dashboard
case "returns":        IOSReturnsPage()            // 7. Problem solving
// "wishlist" → future
```

Update the tab list/picker to show these in order with appropriate icons.

### Step 2: Remove IOSUnifiedOrderPage

Delete or gut the file. If deleting causes build errors, replace the body with a redirect:

```swift
struct IOSUnifiedOrderPage: View {
    var body: some View {
        Text("This page has been replaced. Use Job Orders → Create JPO.")
    }
}
```

Remove any NavigationLink or route that points to it. The JPO creation flow (from 30A-E) handles all order creation now.

### Step 3: Fix SupplierPickerSheet force-unwrap

Find `item.supplier.id!` (line ~32) and replace with safe unwrapping:

```swift
guard let supplierId = item.supplier.id else { return }
```

Also fix the `#if os(iOS)` platform guard.

### Step 4: Update NavigationConfig routes

Add/update routes for the new tab order:
- `/orders/jpos` → IOSJPOsPage
- `/orders/procurement` → IOSProcurementPage
- `/orders/purchase-orders` → IOSPurchaseOrdersPage
- `/orders/parts-mgmt` → IOSPartsOrderManagementPage
- `/orders/stage-planner` → IOSOrderStagingPage
- `/orders/approvals` → IOSApprovalsPage
- `/orders/returns` → IOSReturnsPage

Remove the route for `/orders/unified-order` if it exists.

## Success Criteria

- [ ] OrdersRouter shows tabs in workflow order (JPO first, Returns last)
- [ ] IOSUnifiedOrderPage removed or redirected
- [ ] SupplierPickerSheet force-unwrap fixed
- [ ] Platform guard removed from SupplierPickerSheet
- [ ] NavigationConfig routes updated
- [ ] No broken navigation links
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 29D Results (YYYY-MM-DD)
- Router updated to workflow tab order
- UnifiedOrderPage removed/redirected
- SupplierPicker force-unwrap fixed
- Routes updated
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
