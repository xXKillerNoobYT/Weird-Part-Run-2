---
id: PE-042
title: Cart Mode UI — Multi-Bin Move Flow
status: pending
github_issue: "#138"
service_methods_done: true
commit: 71aa8bf
---

# PE-042: Cart Mode UI (Warehouse Setup — Cart Mode Multi-Bin Move)

## Background

The service layer is complete (commit 71aa8bf):
- `WarehouseService.moveBinsToArea(binIds: [Int64], targetAreaId: Int64)` — batch moves bins
- `WarehouseService.saveUnitPlacement(unitId: Int64, gridX: Int, gridY: Int, zoneId: Int64?)` — grid placement

The `WizardStepPlacement.swift` file already has the drag-and-drop floor plan (PE-040 ✅). Cart Mode is a **separate flow** for physically moving bins with a cart.

## What to Build

In `WizardStepPlacement.swift` (or the appropriate Warehouse Setup file):

### 1. Cart Mode Toggle
Add a "Cart Mode" button/toggle in the placement step toolbar.
- When active: show a "Cart" overlay/banner indicating cart mode is live
- Each bin in the floor plan gets a checkmark overlay — tap to add to cart

### 2. Bin Selection
- `@State private var cartBinIds: Set<Int64> = []`
- Tapping a bin in Cart Mode toggles it in/out of `cartBinIds`
- Selected bins show a cart icon or filled checkmark
- Badge shows count of selected bins

### 3. Place Cart Sheet
A sheet that appears when the user taps "Place Cart" (only enabled if `cartBinIds.count > 0`).

Sheet contains:
- Title: "Place Cart — N bins selected"
- Area picker: list of `WarehouseStorageArea` records to choose destination
- "Move Bins" button — calls `warehouseService.moveBinsToArea(binIds: Array(cartBinIds), targetAreaId: selectedAreaId)`
- On success: clear `cartBinIds`, dismiss sheet, reload floor plan
- On error: show `actionError` in the sheet

### 4. Exit Cart Mode
- "Done" / "Cancel" button exits cart mode and clears `cartBinIds`

## Files to Modify
- `WizardStepPlacement.swift` — primary target
- Or whichever file renders the warehouse floor plan in setup context

## Constraints
- Do NOT modify `WarehouseService.swift` — service layer is done
- Use `guard let service = appCore.warehouseService` before calling service
- Use `guard let userId = appCore.currentUser?.id` if any write needs userId
- Sheet must use `.interactiveDismissDisabled(isMoving)` during the move operation
- Bin move is async — use `Task { }` and `@State var isMoving = false`

## Acceptance Criteria
1. Cart Mode toggle visible in warehouse setup placement step
2. Tapping bins in Cart Mode adds/removes them from selection
3. "Place Cart" sheet shows area picker and moves bins on confirm
4. Success clears selection and reloads floor plan
5. Error shows inline error in sheet (not a silent failure)
6. No `?? 0` or `?? 1` fallbacks anywhere in the new code
