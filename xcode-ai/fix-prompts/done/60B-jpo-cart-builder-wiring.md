# 60B — JPO Cart Builder Wiring
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

The "+" button on `IOSJPOsPage` currently shows `CreateJPOSheet` as a modal sheet. `CreateJPOSheet` creates an empty JPO with no line items — the user then has to separately add parts. The full cart builder `IOSJPOCreationPage` exists but is unreachable from the JPO list. Fix: make the "+" button navigate to `IOSJPOCreationPage` (push navigation) instead of presenting `CreateJPOSheet`. Keep `CreateJPOSheet` only for editing existing JPO metadata.

## Task

### Step 1: Modify IOSJPOsPage

In `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`:

**1a.** Remove `case createJPO` from the `ActiveSheet` enum. It will no longer be a sheet — it becomes a navigation destination.

**1b.** Add a `@State` property for navigation:

```swift
@State private var navigateToCreate = false
```

**1c.** Change the toolbar "+" button from:

```swift
Button { activeSheet = .createJPO } label: {
    Image(systemName: "plus")
}
```

To:

```swift
NavigationLink(destination: IOSJPOCreationPage().environmentObject(appCore)) {
    Image(systemName: "plus")
}
```

**1d.** Remove the `.createJPO` case from the `sheetContent(for:)` switch statement. The switch should only handle `.qrScanner` and `.scannedJPODetail`.

**1e.** Delete the import/reference to `CreateJPOSheet` if it was the only place using it from JPO list context. Do NOT delete the `CreateJPOSheet.swift` file itself — it may be used elsewhere for editing.

### Step 2: Verify IOSJPOCreationPage has an onSave callback

In `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift`:

Check that after submitting the JPO, it calls `dismiss()`. The page already has `@Environment(\.dismiss) private var dismiss`. Verify the submit action calls `dismiss()` after successful creation. If it does, navigation pop will return the user to the JPO list. If not, add `dismiss()` at the end of the submit success path.

### Step 3: Ensure the JPO list wraps in a NavigationStack

The `IOSJPOsPage` must be inside a `NavigationStack` for the `NavigationLink` to work. Check the `OrdersRouter` that embeds this page — it should already provide a NavigationStack from the parent router. If the page has its own `NavigationStack` wrapper, ensure it doesn't double-stack. If the parent router does NOT provide a NavigationStack, wrap the page body in one.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift` — change "+" from sheet to NavigationLink
2. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — verify dismiss() on submit
3. `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — verify NavigationStack context (read only, modify if needed)

## Success Criteria

- [ ] Tapping "+" on JPO list pushes `IOSJPOCreationPage` (full cart builder) onto the navigation stack
- [ ] `CreateJPOSheet` is no longer shown from the "+" button
- [ ] The cart builder page has a working back button that returns to the JPO list
- [ ] After submitting a JPO in the cart builder, the user returns to the JPO list
- [ ] `CreateJPOSheet.swift` file still exists (not deleted)
- [ ] QR scanner sheet still works from the toolbar
- [ ] No compilation errors
