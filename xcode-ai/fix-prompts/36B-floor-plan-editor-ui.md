# 36B — Warehouse Floor Plan Editor UI

> **Chain position:** 36A → **36B** → 36C → 36D
> **Prerequisite:** 36A (tables + models + service methods exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files — use WarehouseService
2. DO NOT use `#if os(iOS)` guards

## Context

The Locations page needs a visual floor plan editor where users can place storage units on a grid. See `docs/plans/ios-warehouse-pages.md` (Locations section).

## Task

### Rebuild WarehouseLocationsPage

Replace the current text-list view with a multi-layer system:

**Top level:** Floor plan selector + grid view
**Drill into unit:** Levels, areas, bins
**Long press unit:** Rotate 90°, show front face, edit, remove

### Floor Plan Grid View
- Grid based on room measurements (1 square = 2ft × 2ft default)
- Pinch to zoom, drag to pan
- Storage units shown as colored rectangles on the grid
- Floor features (doors, walkways) shown as labeled zones
- Tap unit → drill into levels/areas
- Long press unit → context menu (rotate, front face, edit, remove)

### Toolbar: Add Units
Horizontal scroll of unit types:
- [+ Shelf] [+ Pipe Rack] [+ Gang Box] [+ Wall Mount] [+ Cabinet] [+ Pallet Rack] [+ Floor Area] [+ Custom]
- Tap to create → configure sheet → place on grid

### Unit Configuration Sheet
When creating or editing a unit:
- Name, type, dimensions (ft + in)
- Number of levels (for shelving: G0, S01-S0N, ST)
- Areas per level (different count per level)
- Row assignment (R01, R02...)
- Orientation + front face direction
- Movable toggle + job-ready toggle
- For movable with home: assign home area

### Drill-In: Unit Detail
Tap a unit on the floor plan → shows levels:
```
Shelf A (R01-U01)
├── Ground Zero (G0) — 2 areas
├── Level 1 (S01) — 4 areas
├── Level 2 (S02) — 8 areas
├── Level 3 (S03) — 12 areas
├── Level 4 (S04) — 4 areas
└── Top (ST) — 1 area

Tap a level → shows areas:
Level 2 (S02) — 8 areas
├── A01: ½" Copper Fitting (45), ¾" Copper Fitting (12)
├── A02: Copper Tee (22)
├── A03: Wire Nuts Red (8), Wire Nuts Yellow (15)
├── A04: Solder (5) + Bin B01: Flux Paste
├── A05: (empty)
├── A06: (empty)
├── A07: (empty)
└── A08: (empty)

Tap an area → shows contents + actions:
[Assign Part] [Add Bin] [Start Audit] [View on Floor Plan]
```

### Sticker Checklist Integration
After configuring a unit, show the sticker checklist:
- Auto-generated location codes for all levels + areas
- Checkboxes to mark as sticker written/placed
- "Write this on a sticker: R01-U01-S02-A04"

### Movable Storage Section
Below the floor plan grid, show movable items not pinned:
- Gang boxes, crates, tool bags at shop
- Show current location (shop/truck/trailer/job)
- [View Contents] [Move To...]

### QR Scan Any Location
Scan any QR → shows everything at that location:
- Parts present
- Kits/tools that belong here (+ checked out status)
- Empty spots
- Actions: [Assign Part] [Start Audit] [Navigate Here]

## Success Criteria
- [ ] Floor plan grid view with zoom/pan
- [ ] Drag-and-drop unit placement
- [ ] Long press: rotate, front face, edit, remove
- [ ] Drill-in: unit → levels → areas → parts/bins
- [ ] Sticker checklist after unit configuration
- [ ] Movable storage section below grid
- [ ] QR scan shows full location contents
- [ ] Project builds with no errors
