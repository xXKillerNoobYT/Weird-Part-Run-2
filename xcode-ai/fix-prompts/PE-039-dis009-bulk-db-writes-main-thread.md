# PE-039: Move Bulk SQLite Writes Off Main Thread (DIS-009)

**Priority:** Medium
**Source:** dev-improvement-scanner run 9 (2026-04-05)
**DevTODO:** `docs/DevTODO/DIS-009-bulk-db-writes-main-thread.md`

---

## Overview

Two warehouse workflows perform loops of synchronous SQLite writes inside `@MainActor` Button actions. For shops with large inventories (50+ parts, 10+ cart items), this causes brief UI freezes on slower devices (iPhone SE, older iPad).

Fix: wrap both loops in `Task { }` so they run off the main thread, and add `isSaving` state to disable buttons and show feedback while saving.

---

## Fix 1 of 2 — CartManager.placeAllItems()

**File:** `Weird Parts IOS/Features/Warehouse/CartManager.swift`

Find the `placeAllItems()` function (around line 185). It iterates `cartManager.items` calling `appCore.partsService?.updatePart()` synchronously per item.

**Add a `@State` property** at the top of the parent view (wherever `placeAllItems()` is called):
```swift
@State private var isPlacingItems = false
```

**Wrap the loop in Task:**
```swift
private func placeAllItems() {
    isPlacingItems = true
    Task {
        for item in cartManager.items {
            guard let location = placements[item.id],
                  !location.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let partId = item.partId {
                do {
                    try appCore.partsService?.updatePart(id: partId, notes: "Location: \(location)")
                    await MainActor.run { placedItems.insert(item.id) }
                } catch {
                    await MainActor.run {
                        placementError = "Failed to place \(item.name): \(error.localizedDescription)"
                    }
                }
            } else {
                await MainActor.run { placedItems.insert(item.id) }
            }
        }
        await MainActor.run {
            isPlacingItems = false
            if placedItems.count == cartManager.itemCount {
                cartManager.removeAll()
                dismiss()
            }
        }
    }
}
```

**Disable the "Place All" button while saving:**
```swift
Button("Place All Items") { placeAllItems() }
    .disabled(isPlacingItems)
```

**Add a progress indicator** (optional but recommended):
```swift
if isPlacingItems {
    ProgressView("Placing items…")
}
```

---

## Fix 2 of 2 — PartsFlowWizard.saveAllProgress()

**File:** `Weird Parts IOS/Features/Warehouse/PartsFlowWizard.swift`

Find `saveAllProgress(clearDraft:)` (around line 391). It loops `parts` calling `updatePart()` synchronously per part.

Check if `isSaving` already exists in this view. If not, add:
```swift
@State private var isSaving = false
```

**Wrap the DB loop in Task:**
```swift
func saveAllProgress(clearDraft: Bool) {
    guard !isSaving else { return }
    isSaving = true
    Task {
        for item in parts {
            guard item.locationChanged || item.countChanged else { continue }
            do {
                try appCore.partsService?.updatePart(id: item.id, ...)
            } catch {
                await MainActor.run {
                    saveError = "Failed to save \(item.name): \(error.localizedDescription)"
                }
            }
        }
        if clearDraft { clearUserDefaultsDraftKeys() }
        await MainActor.run {
            isSaving = false
            dismiss()
        }
    }
}
```

**Disable Save & Exit / Finish buttons while saving:**
```swift
Button("Save & Exit") { saveAllProgress(clearDraft: false) }
    .disabled(isSaving)

Button("Finish") { saveAllProgress(clearDraft: true) }
    .disabled(isSaving)
```

---

## Verification

1. Add 10+ parts to cart → tap "Place All Items" → UI should remain responsive (no freeze)
2. Load 20+ parts in PartsFlowWizard → tap "Save & Exit" → spinner shows, buttons disabled during save
3. Both buttons should re-enable after completion
4. Test on iPhone SE simulator (slowest supported) for worst-case freeze detection
