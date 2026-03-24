# 29B — Returns Page: ErrorStateView + Console→UI + Smart Cards

> **Chain position:** Independent fix
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 3, IOSReturnsPage
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The returns page has `loadError` state but never displays it. Errors are only printed to console. It uses capsule chips instead of smart card filters and has a platform guard.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReturnsPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/CreateReturnSheet.swift`

## Task

### Step 1: Add ErrorStateView for loadError

The page has `@State private var loadError: String?` but no UI branch for it. Add the error display:

```swift
} else if let error = loadError {
    ErrorStateView(message: error) { loadData() }
}
```

### Step 2: Replace print() with loadError/actionError

Find all `print("[IOSReturnsPage]..."` statements and replace with setting the appropriate error state variable.

### Step 3: Replace capsule chips with smart card filters

Replace the horizontal scroll capsule chip filter with smart card filters (program standard). Cards show counts and act as toggle filters:

```swift
// Smart card filter grid instead of capsule chips
// Each card: tap to filter, tap again for All, shows count
```

Status options for returns: `all`, `pending`, `approved`, `in_transit`, `completed`, `rejected`

### Step 4: Remove `#if os(iOS)` platform guard

Remove platform guard around `.listStyle(.insetGrouped)`.

### Step 5: Fix CreateReturnSheet

- Remove `#if os(iOS)` platform guard
- Replace hardcoded return type strings with constants
- Add `guard let service` error handling (not silent return)

### Step 6: Add ActiveSheet pattern

Replace `.sheet(isPresented: $showCreateReturn)` with ActiveSheet enum.

## Success Criteria

- [ ] ErrorStateView displayed when loadError is set
- [ ] No print() statements for errors — all show in UI
- [ ] Smart card filters replace capsule chips
- [ ] Platform guards removed (both files)
- [ ] ActiveSheet pattern
- [ ] Return type constants instead of hardcoded strings
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 29B Results (YYYY-MM-DD)
- ErrorStateView for loadError
- Console prints → UI error display
- Smart card filters
- Platform guards removed
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
