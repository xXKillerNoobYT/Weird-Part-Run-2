# PE-040 — Warehouse Wizard: Dimensions-First + Drag-and-Drop Placement
# Plan: docs/plans/ios-warehouse-setup-redesign.md (updated Q&A #22)
# GitHub Issue: #22

## Summary
The current `WizardStepPlacement.swift` pre-fills all storage units into Row 1 AND uses
tap-to-place (not drag-and-drop). The owner has confirmed both are wrong:
1. The wizard must start with the user entering grid dimensions (rows × columns)
2. Placement must use true drag-and-drop (not tap-to-select + tap-to-place)

## Root Cause
Grid dimensions are calculated from `floorPlan.widthInches / 60` — never entered by the user.
All units that haven't been explicitly placed default to `gridX=nil, gridY=nil`, which the
existing display code treats as "row 0, col 0" — causing the visual "Row 1" appearance.

## Files to Modify

### `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WizardStepPlacement.swift`

**Complete rewrite of this file.** The new design has two phases:

---

#### Phase A — Dimensions Input (shown when `gridDimensions == nil`)

Add `@State private var gridDimensions: (rows: Int, cols: Int)?`

Show a simple form before the grid:

```
"Define Your Grid"
[  Rows  ] [ Columns ]    ← Steppers (min 1, max 20)
"Example: 3 rows × 5 columns = 15 positions"
[  Confirm Grid  ]  ← Button
```

When user taps "Confirm Grid":
- Save `gridDimensions = (rows: selectedRows, cols: selectedCols)`
- Save to `WarehouseFloorPlan` via a service method if possible, OR hold in `@State`
- Transition to Phase B

---

#### Phase B — Drag-and-Drop Placement Grid (shown when `gridDimensions != nil`)

Replace the existing tap-based `gridCell` with a `DragDropGrid`:

```swift
struct DragDropGrid: View {
    // Grid size from gridDimensions
    // Each cell: 60×60pt, labeled "R1C1", "R1C2", etc.
    // Unplaced units shown in a sidebar/bottom panel
    // User long-presses a unit chip to begin drag
    // Dragging over a cell highlights it
    // Releasing over a cell calls placeUnit(row:col:)
}
```

**Drag implementation using SwiftUI DragGesture:**
- Each unplaced unit chip has a `.onDrag { NSItemProvider(object: unitId as NSString) }` modifier
- Each grid cell has a `.onDrop(of: [.text], delegate: ...)` conforming to `DropDelegate`
- `performDrop` calls `placeUnit(unitId:row:col:)`
- Already-placed units can be dragged again (within the grid) to reposition

**Remove:**
- The `selectedUnitId` tap-select pattern
- The "Tap a unit, then tap a grid cell" instruction text

**Keep:**
- The `placeUnit(row:col:)` function (update its signature to `placeUnit(unitId:row:col:)`)
- The `unplacedUnitsBar` (or rename to sidebar) — reuse as the drag source
- The `placedUnitsList` legend at bottom
- The service call `WarehouseService.saveUnitPlacement(unitId:row:col:zoneId:)`

---

## Verification

1. Build — zero errors
2. Run on simulator — wizard Step 4 shows the dimensions form first
3. Enter "2 rows × 3 cols" → Confirm Grid → grid shows 2×3 cells
4. Long-press a unit chip → drag it over a cell → release → unit appears in that cell
5. All units placed → "All units placed!" message shows
6. Navigate back to step 3 → return to step 4 → placed positions are restored

## Notes

- `WarehouseFloorPlan` model is in `FloorPlanModels.swift`
- If there is no method to save grid dimensions to the floor plan, add:
  `WarehouseService.updateFloorPlanGrid(floorPlanId: Int64, rows: Int, cols: Int) throws`
  with SQL: `UPDATE warehouse_floor_plans SET grid_rows = ?, grid_cols = ? WHERE id = ?`
  (add `grid_rows` and `grid_cols` columns if not already present in the floor plan table)
- If `grid_rows`/`grid_cols` columns don't exist in the schema, create a migration for them
  (check existing migrations in `core/Sources/WiredPartCore/Migrations/` — find the highest
  numbered one and create the next)
- Keep `@EnvironmentObject private var appCore: AppCore` and `let floorPlanId: Int64`
- If `DropDelegate` requires iOS 16+, check the deployment target — if iOS 17+, use
  `.dropDestination(for: String.self)` instead (simpler API)
