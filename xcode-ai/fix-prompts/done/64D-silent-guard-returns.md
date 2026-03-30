# 64D — Silent Guard Returns: Fix Last 6 Missing Error States

> **Chain position:** After 65A, before 64E
> **Priority:** MEDIUM — silent failures confuse users (action appears to do nothing)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Six `guard` statements silently return without setting error state, making the UI appear broken when the guard fails. Fix all of them.

**Read these files first:**
- `Features/Orders/IOSWishlistPage.swift` — 5 instances (lines ~301, 313, 325, 336, 347)
- `Features/Dashboard/IOSDashboardQRScannerPage.swift` — 1 instance (line ~704)

## Task

### Part 1: IOSWishlistPage.swift — 5 silent `guard let id` returns

There are 5 action methods (`approveItem`, `dismissItem`, `sendToProcurement`, `reopenItem`, `deleteItem`) that each have:

```swift
guard let id = item.id else { return }
```

These silently fail if the wishlist item has no ID (corrupted data). Change each to set an error:

```swift
guard let id = item.id else {
    loadError = "Invalid item — missing ID"
    return
}
```

Apply this to ALL 5 instances. The `loadError` state variable already exists on this page.

### Part 2: IOSDashboardQRScannerPage.swift — 1 silent service guard

Line ~704 has:

```swift
guard let service = appCore.warehouseService else { return nil }
```

This is in a function that returns an optional. Change to:

```swift
guard let service = appCore.warehouseService else {
    scanError = "Warehouse service not available"
    return nil
}
```

Verify that `scanError` (or equivalent error state variable) exists on this page. If the page uses a different error variable name, use that instead.

### Part 3: Verify no other silent guards remain

Search ALL files under `Features/` for this pattern:

```
guard let.*Service.*else { return }
guard let.*service.*else { return }
guard let.*Service.*else { return nil }
guard let.*service.*else { return nil }
```

Any match that does NOT set an error state variable (`loadError`, `saveError`, `scanError`, `actionMessage`, etc.) must be fixed using the same pattern.

Exclude guards where the service is genuinely optional and nil is expected (add a `// Service not needed here` comment if so).

## Success Criteria

- [ ] All 5 `guard let id = item.id` in IOSWishlistPage set `loadError`
- [ ] IOSDashboardQRScannerPage service guard sets error state
- [ ] No remaining silent service/id guards in Features/ (verified by grep)
- [ ] Project builds with zero errors
- [ ] Log entry added to `xcode-ai/prompt-results-log.md`

## Log Entry

```
## Prompt 64D — Silent Guard Returns
**Date:** YYYY-MM-DD
**Status:** ✅ / ❌
**Files changed:** (list)
**Silent guards fixed:** X
**Build:** PASS / FAIL
```
