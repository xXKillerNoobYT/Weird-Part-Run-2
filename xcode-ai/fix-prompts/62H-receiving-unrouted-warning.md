# 62H — Add Confirmation Dialog for Unrouted Items When Completing Receiving
> Chain position: Standalone

## Task

When a user completes a receiving session, any items without a routing decision (no job assignment, no warehouse location override) silently go to default warehouse stock. Add a confirmation dialog that warns the user about unrouted items before completing.

### Step 1: Add state for the confirmation dialog

In `IOSReceiveShipmentPage.swift`, add these `@State` properties:

```swift
@State private var showUnroutedWarning = false
@State private var unroutedCount = 0
```

### Step 2: Find the "Complete Receiving" button action

Locate the button or action that calls the completion function (e.g., `completeReceiving()` or `completeSession()`). It likely triggers a service call like `ordersService.completeReceivingSession(...)`.

### Step 3: Intercept the completion to check for unrouted items

Before calling the service, count how many items have no routing decision:

```swift
// Count items with no explicit routing
let unrouted = receivedItems.filter { item in
    // An item is "unrouted" if it has received quantity > 0 but no routing decision
    item.receivedQty > 0 && !routingDecisions.keys.contains(item.id ?? 0)
}

if !unrouted.isEmpty {
    unroutedCount = unrouted.count
    showUnroutedWarning = true
    return  // Don't complete yet — wait for confirmation
}

// If all items are routed, complete immediately
await performCompletion()
```

### Step 4: Add the confirmation dialog

Add a `.confirmationDialog` modifier to the view:

```swift
.confirmationDialog(
    "Unrouted Items",
    isPresented: $showUnroutedWarning,
    titleVisibility: .visible
) {
    Button("Continue Anyway") {
        Task {
            await performCompletion()
        }
    }
    Button("Go Back and Route", role: .cancel) {}
} message: {
    Text("\(unroutedCount) item\(unroutedCount == 1 ? "" : "s") ha\(unroutedCount == 1 ? "s" : "ve") no routing decision. \(unroutedCount == 1 ? "It" : "They") will go to default warehouse stock. Continue?")
}
```

### Step 5: Extract completion logic

If the completion logic isn't already in a separate function, extract it:

```swift
private func performCompletion() async {
    // ... existing completion code that was in the button action ...
}
```

### Adapt to actual code structure:

The above is a pattern. You MUST read the actual file to find:
- The exact variable name for received items (might be `items`, `sessionItems`, `receivedLines`, etc.)
- The exact routing data structure (might be `routingDecisions`, `itemRoutes`, etc.)
- The exact completion function name and parameters
- Where to place the `.confirmationDialog` modifier

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

## Success Criteria
- [ ] Tapping "Complete" with unrouted items shows a confirmation dialog
- [ ] Dialog message shows exact count of unrouted items
- [ ] "Continue Anyway" completes the session normally
- [ ] "Go Back and Route" dismisses the dialog without completing
- [ ] If ALL items are routed, completion proceeds immediately without dialog
- [ ] No compile errors
