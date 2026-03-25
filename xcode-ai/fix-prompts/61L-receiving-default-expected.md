# 61L — Default Received Quantities to Expected Quantity

> **Chain position:** **61L** (standalone)
> **Issue:** T2-14
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. Default to expected quantity, NOT hardcoded values
2. User must be able to CHANGE the pre-filled quantity (it's a default, not locked)
3. DO NOT auto-submit — user must still review and confirm
4. Highlight items where received differs from expected
5. Project must build with zero errors when done

## Context

When receiving a PO shipment, every line item's received quantity starts at 0. Workers must manually enter the quantity for EVERY item, even when the full expected quantity arrived (which is the common case). This is tedious for POs with 20+ line items.

The fix: default received quantities to the expected quantity. Workers only need to adjust the few items that were short-shipped or over-shipped. This flips the workflow from "enter everything" to "fix the exceptions."

## File to Modify

`Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

## Task

### 1. Find the Received Quantities State

Look for:
- `@State private var receivedQuantities: [Int64: Int]` or similar dictionary
- `@State private var receivedQty: [...]`
- Individual `@State` per line item

### 2. Initialize to Expected Quantities

Where the quantities dictionary is initialized (likely in `.task` or `.onAppear`):

```swift
// BEFORE:
.task {
    // Load line items
    lineItems = try await loadLineItems()
    // Quantities default to 0
    for item in lineItems {
        receivedQuantities[item.id] = 0
    }
}

// AFTER:
.task {
    // Load line items
    lineItems = try await loadLineItems()
    // Default received to expected — user adjusts for short shipments
    for item in lineItems {
        receivedQuantities[item.id] = item.expectedQuantity
    }
}
```

### 3. Show "Full Shipment" Indicator

Add a banner at the top indicating the default:
```swift
HStack(spacing: 8) {
    Image(systemName: "info.circle")
        .foregroundColor(.blue)
    Text("Quantities pre-filled from PO. Adjust any short or extra items.")
        .font(.caption)
        .foregroundColor(.secondary)
}
.padding(.horizontal)
.padding(.vertical, 8)
.background(Color.blue.opacity(0.05))
.cornerRadius(8)
```

### 4. Highlight Adjusted Items

When a user changes a quantity to differ from expected, highlight that row:

```swift
var isAdjusted: Bool {
    receivedQuantities[item.id] != item.expectedQuantity
}

// On the row:
.background(
    isAdjusted ? Color.orange.opacity(0.1) : Color.clear
)
```

### 5. Show Discrepancy Summary

Before the "Complete Receiving" button, show a summary of adjustments:

```swift
let adjustedItems = lineItems.filter { receivedQuantities[$0.id] != $0.expectedQuantity }

if !adjustedItems.isEmpty {
    Section("Quantity Adjustments") {
        ForEach(adjustedItems) { item in
            HStack {
                Text(item.partName)
                Spacer()
                Text("Expected: \(item.expectedQuantity)")
                    .foregroundColor(.secondary)
                Text("Received: \(receivedQuantities[item.id] ?? 0)")
                    .fontWeight(.bold)
                    .foregroundColor(
                        (receivedQuantities[item.id] ?? 0) < item.expectedQuantity
                            ? .orange : .green
                    )
            }
        }
    }
} else {
    Text("All quantities match expected — full shipment received")
        .font(.subheadline)
        .foregroundColor(.green)
        .padding()
}
```

### 6. Add "Mark All Received" / "Clear All" Buttons

```swift
HStack {
    Button("Reset to Expected") {
        for item in lineItems {
            receivedQuantities[item.id] = item.expectedQuantity
        }
    }
    .font(.caption)

    Spacer()

    Button("Clear All") {
        for item in lineItems {
            receivedQuantities[item.id] = 0
        }
    }
    .font(.caption)
    .foregroundColor(.red)
}
```

## Success Criteria

- [ ] Received quantities default to expected quantity on page load
- [ ] Info banner explains "pre-filled from PO, adjust as needed"
- [ ] Adjusted items (received differs from expected) highlighted orange
- [ ] Discrepancy summary shown before completing
- [ ] "Reset to Expected" and "Clear All" buttons available
- [ ] User can still manually change any quantity
- [ ] Project builds with zero errors
