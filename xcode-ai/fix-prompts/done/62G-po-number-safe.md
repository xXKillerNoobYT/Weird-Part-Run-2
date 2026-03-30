# 62G — Fix PO Number Generation to Prevent Duplicates
> Chain position: Standalone

## Task

PO numbers are generated using `COUNT(*) FROM purchase_orders` + 1, which produces duplicates if any POs have been deleted. Fix both occurrences to use `MAX` on the numeric portion instead.

### Problem:

In `OrdersService.swift`, there are TWO places where PO numbers are generated:

**Location 1 (~line 1274-1278):** Inside `consolidateJPOsToPOs` method:
```swift
let count = try Int.fetchOne(
    dbConn,
    sql: "SELECT COUNT(*) FROM purchase_orders"
) ?? 0
let poNumber = String(format: "PO-%05d", count + 1)
```

**Location 2 (~line 1577-1581):** Inside another PO creation method:
```swift
let count = try Int.fetchOne(
    dbConn,
    sql: "SELECT COUNT(*) FROM purchase_orders"
) ?? 0
let poNumber = String(format: "PO-%05d", count + 1)
```

### Fix for BOTH locations:

Replace the COUNT-based generation with MAX-based:

```swift
let maxNum = try Int.fetchOne(
    dbConn,
    sql: """
        SELECT COALESCE(
            MAX(CAST(SUBSTR(po_number, 4) AS INTEGER)),
            0
        ) FROM purchase_orders
        WHERE po_number LIKE 'PO-%'
        """
) ?? 0
let poNumber = String(format: "PO-%05d", maxNum + 1)
```

### How this works:

- `SUBSTR(po_number, 4)` extracts everything after "PO-" (e.g., "00042" from "PO-00042")
- `CAST(... AS INTEGER)` converts to int (strips leading zeros)
- `MAX(...)` gets the highest PO number ever assigned
- `COALESCE(..., 0)` handles empty table
- This means deleting PO-00003 won't cause the next PO to reuse "00003"

### Edge case:

If someone manually edited a po_number to not follow the "PO-XXXXX" format, the `WHERE po_number LIKE 'PO-%'` filter ensures those rows are ignored.

## Files to Modify

- `core/Sources/WiredPartCore/Services/OrdersService.swift` — two locations (~line 1274 and ~line 1577)

## Success Criteria
- [ ] Both PO number generation sites use MAX instead of COUNT
- [ ] Deleting a PO does not cause the next PO to reuse the deleted number
- [ ] New POs always get the next number after the highest existing PO number
- [ ] Empty table produces PO-00001
- [ ] No compile errors
