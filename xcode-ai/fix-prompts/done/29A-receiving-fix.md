# 29A — Receiving Page: Hardcoded User ID + ActiveSheet + Platform Guard

> **Chain position:** Independent fix
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 3, IOSReceiveShipmentPage
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The receiving page has a critical bug: hardcoded user ID `1` instead of using the current logged-in user. It also uses `.sheet(isPresented:)` instead of the ActiveSheet pattern and has a platform guard.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

## Task

### Step 1: Fix hardcoded user ID

Search for all instances of hardcoded user IDs (the number `1` used as a user ID parameter). Replace with:

```swift
guard let userId = appCore.currentUser?.id else {
    // Show error — user not logged in
    return
}
```

Check lines around 356 and 394 specifically. Replace every hardcoded `1` used as `startedBy:`, `completedBy:`, or any user ID parameter.

### Step 2: Replace `.sheet(isPresented:)` with ActiveSheet

Find all `@State private var show___` booleans used for sheets. Replace with:

```swift
@State private var activeSheet: ActiveSheet?

private enum ActiveSheet: Identifiable {
    case qrScanner
    // Add other sheet cases as needed

    var id: String { String(describing: self) }
}
```

Replace `.sheet(isPresented:)` with `.sheet(item: $activeSheet)` and add a `sheetContent(for:)` router.

### Step 3: Remove `#if os(iOS)` platform guard

Remove the platform guard around `.listStyle(.insetGrouped)`. Keep the iOS code.

### Step 4: Fix any `guard let service` silent failures

Ensure all `guard let service = appCore.___Service else { return }` set `loadError` before returning.

## Success Criteria

- [ ] No hardcoded user IDs — all use `appCore.currentUser?.id`
- [ ] ActiveSheet enum pattern with single `.sheet(item:)`
- [ ] Platform guard removed
- [ ] Guard failures set loadError
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 29A Results (YYYY-MM-DD)
- Fixed hardcoded user ID 1 → currentUser
- ActiveSheet pattern applied
- Platform guard removed
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
