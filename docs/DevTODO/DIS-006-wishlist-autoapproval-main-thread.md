---
source: dev-improvement-scanner (2026-04-04)
severity: High
category: Performance — Main Thread Blocking
status: partial — core fixed 2026-04-04
github_issue: PENDING (gh not available, file manually)
---

# DIS-006: WishlistService.processAutoApprovals() Blocks Main Thread

## Problem
`WishlistService.getSectionedItems()` calls `processAutoApprovals()` synchronously at the top of every invocation (line ~321). `processAutoApprovals()` performs multiple DB writes in a loop — one `UPDATE` per expired item. SwiftUI's `.task { }` modifier runs on `@MainActor`, so these writes block the main thread until all auto-approvals complete.

On a large wishlist with many expired auto-approve items, this can cause the UI to stutter or freeze briefly each time the Wishlist page loads.

## Files
- `core/Sources/WiredPartCore/Services/WishlistService.swift` — lines 319-366
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSWishlistPage.swift` — `loadData()` calls `getSectionedItems()`

## Fix (paste into Xcode AI)

Split the auto-approval step out of `getSectionedItems()` and run it as a detached background task in the view's `loadData()`:

```swift
// In IOSWishlistPage loadData():
func loadData() {
    isLoading = sections == nil
    Task.detached(priority: .utility) {
        // Run auto-approvals in background before fetching sections
        _ = try? AppCore.shared.wishlistService.processAutoApprovals(by: "System (Auto)")
        let result = try? AppCore.shared.wishlistService.getSectionedItems(statusFilter: ...)
        await MainActor.run {
            sections = result
            isLoading = false
        }
    }
}
```

And remove the `processAutoApprovals()` call from the top of `getSectionedItems()` in WishlistService so it's no longer automatically embedded in every read.

## Alternatively (simpler fix)
Make `getSectionedItems()` NOT call `processAutoApprovals()` inline. Instead call `processAutoApprovals()` only when:
1. The Wishlist page first appears
2. After a refresh action

## Verification
1. Add a pending wishlist item with `auto_approve_at` set to a past date
2. Open the Wishlist page — should see no UI stutter
3. Item should transition to approved state
4. No main thread blocks detected in Instruments
