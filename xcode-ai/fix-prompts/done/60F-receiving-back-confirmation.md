# 60F — Receiving Back Button Confirmation
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

In `IOSReceiveShipmentPage`, when a user has entered received quantities for items and then taps the Back button, ALL entered data is silently discarded. There is no confirmation dialog. This is a critical data-loss bug — a user could spend 10 minutes entering quantities for 20 line items, accidentally tap Back, and lose everything.

## Task

### Step 1: Detect unsaved changes

In `IOSReceiveShipmentPage.swift`, add a computed property that checks whether any receiving work has been done:

```swift
/// True if the user has entered any quantities or made routing decisions.
private var hasUnsavedWork: Bool {
    // Check if any received quantities are > 0
    let hasQuantities = receivedQtys.values.contains(where: { $0 > 0 })
    // Check if any routing decisions were made
    let hasRouting = !routingResults.isEmpty
    return hasQuantities || hasRouting
}
```

### Step 2: Add confirmation state

Add a state variable for the confirmation dialog:

```swift
@State private var showDiscardConfirmation = false
```

### Step 3: Intercept the back navigation

There are two approaches depending on how the page is presented:

**Approach A: If the page is pushed via NavigationLink (navigation stack):**

Add an `interactiveDismissDisabled` modifier and a custom back button:

```swift
.navigationBarBackButtonHidden(hasUnsavedWork)
.toolbar {
    if hasUnsavedWork {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                showDiscardConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
        }
    }
}
.confirmationDialog(
    "Discard Receiving Data?",
    isPresented: $showDiscardConfirmation,
    titleVisibility: .visible
) {
    Button("Keep Working", role: .cancel) { }
    Button("Discard", role: .destructive) {
        // Clear all entered data and dismiss
        receivedQtys = [:]
        routingResults = [:]
        priceVerifications = [:]
        activeSessionId = nil
        sessionItems = []
    }
} message: {
    Text("You have unsaved receiving data. Going back will discard all entered quantities and routing decisions.")
}
```

**Approach B: If the page is presented as a sheet:**

Use `.interactiveDismissDisabled(hasUnsavedWork)` to prevent swipe-to-dismiss, and add a close button that shows the confirmation:

```swift
.interactiveDismissDisabled(hasUnsavedWork)
```

### Step 4: Handle the session view vs list view

The page has two states: the PO list (no session active) and the receiving session (active session with line items). The back confirmation should ONLY apply when `activeSessionId != nil` — i.e., when the user is in an active receiving session. When they're on the PO list view, Back should work normally.

Update the computed property:

```swift
private var hasUnsavedWork: Bool {
    guard activeSessionId != nil else { return false }
    let hasQuantities = receivedQtys.values.contains(where: { $0 > 0 })
    let hasRouting = !routingResults.isEmpty
    return hasQuantities || hasRouting
}
```

### Step 5: Add a "Cancel Session" button inside the receiving session view

When the user is viewing the line items for a receiving session, add a visible "Cancel Session" button at the bottom that also triggers the confirmation:

```swift
// At the bottom of the session items view
if activeSessionId != nil {
    Section {
        Button(role: .destructive) {
            if hasUnsavedWork {
                showDiscardConfirmation = true
            } else {
                // No work done, just go back to PO list
                activeSessionId = nil
                sessionItems = []
                receivedQtys = [:]
                routingResults = [:]
                priceVerifications = [:]
            }
        } label: {
            HStack {
                Image(systemName: "xmark.circle")
                Text("Cancel Receiving Session")
            }
            .frame(maxWidth: .infinity)
        }
    }
}
```

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSReceivingPage.swift` — add confirmation dialog, intercept back navigation

## Success Criteria

- [ ] Tapping Back while quantities are entered shows a confirmation dialog
- [ ] Dialog has two buttons: "Keep Working" (cancel) and "Discard" (destructive)
- [ ] "Keep Working" returns to the receiving session with all data intact
- [ ] "Discard" clears all quantities and returns to the PO list or previous page
- [ ] If no quantities were entered, Back works normally without a dialog
- [ ] "Cancel Receiving Session" button visible at the bottom of the session view
- [ ] Swipe-to-dismiss is blocked when unsaved work exists (if presented as a sheet)
- [ ] No compilation errors
