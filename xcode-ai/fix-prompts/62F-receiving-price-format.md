# 62F — Fix Price Display Format in IOSReceiveShipmentPage (%.5f to %.2f)
> Chain position: Standalone

## Task

In `IOSReceiveShipmentPage.swift`, the price input field for "Different" price verification displays with 5 decimal places (`%.5f`), which is confusing for users entering dollar amounts. Change it to 2 decimal places (`%.2f`).

### Exact change:

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

**Line ~557:** Find this exact code:
```swift
return p > 0 ? String(format: "%.5f", p) : ""
```

**Replace with:**
```swift
return p > 0 ? String(format: "%.2f", p) : ""
```

### Why this matters:

When a user receives a shipment and marks a price as "Different" from the PO, they see a text field pre-filled with something like `12.45000` instead of `12.45`. The extra zeros are confusing and suggest the app wants sub-cent precision, which it does not.

### Do NOT change:

- `PartsPricingPage.swift` — the `%.5f` there is intentional for cost layers that track sub-cent unit costs (e.g., $0.00345 per washer)
- `PricingBulkEditSheet.swift` — the `%.5f` there is for markup percent storage, not display

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

## Success Criteria
- [ ] The "Actual price" text field in the receiving page shows 2 decimal places, not 5
- [ ] Entering a price like "12.50" displays as "12.50" not "12.50000"
- [ ] No changes to PartsPricingPage.swift or PricingBulkEditSheet.swift
- [ ] No compile errors
