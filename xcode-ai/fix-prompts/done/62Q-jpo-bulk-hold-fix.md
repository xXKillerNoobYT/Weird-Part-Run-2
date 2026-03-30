# 62Q — Fix Bulk Hold on IOSJPODetailPage to Prompt for All Selected Items
> Chain position: Standalone

## Task

When multiple JPO line items are selected and the "Hold" action is triggered, the app currently only prompts for a hold reason for the FIRST selected item. The rest get a generic or empty reason. Fix this to either:
- (Option A) Show a single prompt with all selected items listed, applying the same reason to all, OR
- (Option B) Show the prompt once with a summary, letting the user enter one reason that applies to all selected items.

Option A is simpler and preferred.

### Step 1: Find the bulk hold action

In `IOSJPODetailPage.swift`, find the bulk action for "Hold." It likely looks something like:

```swift
Button("Hold") {
    // Current buggy code: only prompts for first item
    holdItem = selectedItems.first
    showHoldReasonAlert = true
}
```

Or it might iterate through selected items but only show the alert once.

### Step 2: Replace with a proper bulk hold flow

Add state for the bulk hold:

```swift
@State private var showBulkHoldSheet = false
@State private var bulkHoldReason = ""
@State private var itemsToHold: [JPOLineDetail] = []  // Adapt type name to actual
```

Replace the bulk hold button action:

```swift
Button("Hold") {
    // Collect ALL selected items, not just the first
    itemsToHold = lineItems.filter { selectedItems.contains($0.id ?? 0) }
    bulkHoldReason = ""
    showBulkHoldSheet = true
}
```

### Step 3: Create the bulk hold sheet

```swift
.sheet(isPresented: $showBulkHoldSheet) {
    NavigationStack {
        Form {
            Section("Items to Hold") {
                ForEach(itemsToHold, id: \.id) { item in
                    HStack {
                        Text(item.partName)
                        Spacer()
                        Text("×\(item.quantity)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Hold Reason") {
                TextField("Why are these items being held?", text: $bulkHoldReason, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Text("This reason will be applied to all \(itemsToHold.count) selected item\(itemsToHold.count == 1 ? "" : "s").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Hold \(itemsToHold.count) Item\(itemsToHold.count == 1 ? "" : "s")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    showBulkHoldSheet = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm Hold") {
                    Task {
                        await applyBulkHold()
                    }
                }
                .disabled(bulkHoldReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    .presentationDetents([.medium])
}
```

### Step 4: Implement the bulk hold action

```swift
private func applyBulkHold() async {
    guard let service = appCore.ordersService else { return }

    for item in itemsToHold {
        guard let itemId = item.id else { continue }
        try? service.updateJPOLineStatus(
            lineId: itemId,
            status: "hold",
            holdReason: bulkHoldReason
        )
    }

    // Clear selection
    selectedItems.removeAll()
    showBulkHoldSheet = false

    // Reload data
    loadData()
}
```

### Adapt to actual code:

Read `IOSJPODetailPage.swift` to find:
- The actual line item type name (might be `JPOLineDetail`, `JPOLineItem`, `LineRow`, etc.)
- The actual property names for part name and quantity
- The actual service method for updating JPO line status
- The actual selection mechanism (might be `Set<Int64>`, `Set<String>`, binding, etc.)
- Whether the hold reason is stored via a separate method or a parameter on the status update

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift`

## Success Criteria
- [ ] Selecting multiple JPO lines and tapping "Hold" shows a sheet listing ALL selected items
- [ ] Single text field for hold reason applies to ALL items
- [ ] Hold reason is required (button disabled when empty)
- [ ] All selected items get status "hold" with the entered reason
- [ ] Selection is cleared after the hold is applied
- [ ] Data reloads after the hold is applied
- [ ] No compile errors
