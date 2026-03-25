# 60J — Rename "Submit to Supplier" to "Mark as Submitted"
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

On `IOSPODetailPage`, the draft PO action button says "Submit to Supplier" but it only changes the PO status to "submitted" in the local database. It does NOT actually send anything to any supplier. Users think tapping this button emails or faxes the PO — it doesn't. Rename the button and add a clarifying note so users understand they still need to contact the supplier separately.

## Task

### Step 1: Rename the button

In `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`, find this line (approximately line 1663):

```swift
actionButton("Submit to Supplier", icon: "paperplane.fill", color: .blue) {
    await transitionPO(to: "submitted")
}
```

Change it to:

```swift
actionButton("Mark as Submitted", icon: "checkmark.circle.fill", color: .blue) {
    showSubmitConfirmation = true
}
```

### Step 2: Add a confirmation dialog with clarifying note

Add a new state variable:

```swift
@State private var showSubmitConfirmation = false
```

Add a `.confirmationDialog` modifier to the view:

```swift
.confirmationDialog(
    "Mark PO as Submitted?",
    isPresented: $showSubmitConfirmation,
    titleVisibility: .visible
) {
    Button("Mark as Submitted") {
        Task { await transitionPO(to: "submitted") }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This changes the PO status to Submitted. You still need to contact the supplier separately (email, phone, or portal) to actually send the order.")
}
```

### Step 3: Add a post-transition banner

After the PO is successfully transitioned to "submitted", show a brief informational banner. Find the `transitionPO` function and add a success message after the status change:

After the successful status update line, set:

```swift
actionMessage = "PO marked as Submitted. Remember to send the order to the supplier."
```

The `actionMessage` state variable already exists on this page and is displayed as a banner.

### Step 4: Update the icon

The old icon was `paperplane.fill` which implies sending. The new icon should be `checkmark.circle.fill` which implies marking/confirming. This was already done in Step 1.

### Step 5: Search for any other references to "Submit to Supplier"

Run a search for the string "Submit to Supplier" across the entire project to catch any other occurrences (e.g., in help text, comments, or other pages):

```bash
grep -rn "Submit to Supplier" "Weird Parts IOS/" --include="*.swift"
```

Update any other occurrences found to use "Mark as Submitted" with appropriate context.

Also search the core module:
```bash
grep -rn "Submit to Supplier" "core/" --include="*.swift"
```

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — rename button, add confirmation dialog, update icon
2. Any other files found by the grep in Step 5

## Success Criteria

- [ ] Button text reads "Mark as Submitted" (not "Submit to Supplier")
- [ ] Button icon is `checkmark.circle.fill` (not `paperplane.fill`)
- [ ] Tapping the button shows a confirmation dialog explaining that the user must contact the supplier separately
- [ ] After confirming, the PO status changes to "submitted" (same behavior as before)
- [ ] After confirming, a banner message reminds the user to send the order to the supplier
- [ ] No other occurrences of "Submit to Supplier" remain in the codebase
- [ ] No compilation errors
