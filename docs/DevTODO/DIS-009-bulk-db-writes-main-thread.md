---
source: dev-improvement-scanner (2026-04-05)
severity: Medium
category: Performance — Main Thread Blocking
status: CLOSED — Both fixes confirmed in working tree 2026-04-07 (hunt-fix run 14). PartsFlowWizard wrapped in Task{} (PE-039, page-rebuild-enforcer 2026-04-06). CartManager.placeAllItems() also wrapped in Task{} with isPlacingItems lifecycle + interactiveDismissDisabled. Both locations fully async.
github_issue: PENDING (gh not available, file manually)
---

# DIS-009: Bulk SQLite Writes Execute Synchronously on Main Thread

## Problem
Two recently-added workflows perform loops of SQLite writes synchronously inside SwiftUI
`Button` actions (which run on `@MainActor`). For shops with large inventories or carts,
this causes brief UI freezes.

### Location 1: CartManager.placeAllItems()
**File:** `Features/Warehouse/CartManager.swift:185-210`

The "Place All Items" button iterates `cartManager.items` and calls
`appCore.partsService?.updatePart()` synchronously per item — one DB write per cart item,
all on the main thread.

### Location 2: PartsFlowWizard.saveAllProgress() — DB write loop
**File:** `Features/Warehouse/PartsFlowWizard.swift:391-410`

The "Save & Exit" mid-wizard button iterates all `parts` (potentially 100+ for large shops)
and conditionally calls `updatePart()` synchronously per part.

## Fix (paste into Xcode AI)

### CartManager — wrap placeAllItems in Task

```swift
private func placeAllItems() {
    Task {
        for item in cartManager.items {
            guard let location = placements[item.id],
                  !location.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let partId = item.partId {
                do {
                    try appCore.partsService?.updatePart(id: partId, notes: "Location: \(location)")
                    await MainActor.run { placedItems.insert(item.id) }
                } catch {
                    await MainActor.run { placementError = userFriendlyError(error, context: "place item") }
                }
            } else {
                await MainActor.run { placedItems.insert(item.id) }
            }
        }
        await MainActor.run {
            if placedItems.count == cartManager.itemCount {
                try? await Task.sleep(for: .seconds(0.5))
                cartManager.removeAll()
                dismiss()
            }
        }
    }
}
```

### PartsFlowWizard — wrap DB loop in Task

In `saveAllProgress(clearDraft:)`, wrap the `for item in parts { ... }` loop in a
`Task { }` block. Set `isSaving = true` before and `isSaving = false` after. Add a
`@State private var isSaving = false` and disable the save/finish buttons while saving.

## Verification
1. Add 10+ items to cart, tap "Place All" — UI should remain smooth
2. Load 50+ parts in PartsFlowWizard, tap "Save & Exit" — no freeze
3. Test on iPhone SE (A9 — slowest supported chip) for worst-case timing
