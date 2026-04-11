# iOS Warehouse Setup Redesign Plan

## What This Does (Plain English)
The warehouse setup wizard is too pushy and doesn't go through enough detail. This redesign makes setup optional, progressive (stop and resume anytime), and detailed enough to fully map a real warehouse — from floor plan down to individual bin positions on shelves.

## Why We Need This
The current wizard forces setup when users may just want to start using the app. It also assigns everything to "Row 1" without proper placement, making the warehouse data useless for actual operations.

## Current State
- Warehouse Setup Wizard exists but is incomplete
- Forces warehouse setup before app is usable
- No visual floor plan placement
- No bin number system
- Assigns everything to Row 1 automatically

## Owner Decisions Applied
- **Optional** — app fully usable without warehouse setup (Clock In, Parts, Orders all work independently)
- **Two independent flows that work together:**
  - **Parts Flow**: Parts list → count each part → assign location (standalone, works without warehouse map)
  - **Warehouse Floor Plan Flow**: Full physical mapping from size → zones → units → placement → shelves → areas → bin types → bin numbers → part assignment → count verification
- **Progressive** — can stop at any step and resume. No forcing. Save progress automatically.
- **Visual drag-and-drop** for floor plan placement (shelves placed on warehouse floor plan visually)
- **Menu-based** for detailed work (bin numbers, areas on shelves, part assignments)
- **"Cart" holding mode** for moving multiple bins/parts at once — when removing from cart, specifies exact placement (shelf, row, area)
- **Bin numbers** — bins are small boxes on shelves, NOT location-locked. Can be moved. Each has a unique bin number.
- **Current state**: Warehouse is partially set up but messy. Need to add/sort things gradually without being rushed.
- **At any point**: Can go back and edit anything.

## Setup Tiers

### Tier 0 — App Usable (No Setup Required)
Clock In, Parts catalog, Orders, Reports — all work.
Warehouse-dependent features show "Setup required" with link to wizard.

### Tier 1 — Parts Flow Only
1. Add parts to catalog
2. Set counts per part
3. Optionally assign general location (e.g., "Shelf A" as free text, no floor plan needed)

### Tier 2 — Warehouse Floor Plan (Physical Layout)
1. **Define Size** — warehouse dimensions (L × W, optional height)
2. **Define Zones** — draw/label areas inside (drag zones on floor plan grid):
   - Zone types: staging, storage, receiving, returns, office, tool storage, custom
3. **Define Storage Units** — for each zone, add units:
   - Unit types: shelf rack, bin rack, pallet position, work bench, cabinet, custom
   - Properties: name, dimensions, unit type
4. **Place Units on Floor Plan** — drag-and-drop units onto the zone map
   - Visual grid-based placement (not pixel-perfect — row/column grid within zone)
   - CRITICAL: row number + column position within zone = full address
5. **Define Shelves** — for each unit, add shelves (or equivalent):
   - Shelf number (1 from bottom), optional label
6. **Define Areas on Shelf** — for each shelf, add areas:
   - Area name/number (A, B, C or 1, 2, 3)
   - Storage type: bins, open storage
7. **Define What's Stored** — per area:
   - Type: parts, kits, tools, supplies, maintenance items
8. **If Parts + Bins:**
   - Bin count (how many bins in this area)
   - Bin numbers (sequential starting from where area begins, or custom)
9. **Link Parts to Bins/Areas:**
   - Open the part from catalog → assign to bin number or open area
   - OR: Open the bin/area → add parts from catalog
10. **Count Verification** — once all parts assigned, do a count pass
11. **Complete** — when all units in all zones mapped, setup is complete

### Moving Cart Mode
- Tap "Move Items" → enter Cart mode
- Tap bins/parts to add to Cart (highlighted)
- Exit zone/shelf → "Place Cart" → specify destination (zone → unit → shelf → area → position)
- Confirm placement → all items moved in batch

## Files to Create

### New Migration
```sql
-- warehouse_floor_plans: one per warehouse location
-- warehouse_zones: areas within floor plan
-- warehouse_units: physical storage units (shelves, racks, etc.)
-- warehouse_unit_placements: x/y position on floor plan grid
-- warehouse_shelves: rows within a unit
-- warehouse_shelf_areas: sections on a shelf
-- warehouse_bins: individual bins within an area (moveable)
-- warehouse_bin_parts: parts assigned to bins (links parts_colors to bins)
```
(Check existing warehouse schema before adding — some of this may already exist)

### New WarehouseService Methods
- `getFloorPlan(locationId: Int64)` — full nested structure
- `saveUnitPlacement(unitId: Int64, row: Int, col: Int, zoneId: Int64)`
- `moveBinsToArea(binIds: [Int64], targetAreaId: Int64)` — Cart mode operation
- `assignPartToBin(partColorId: Int64, binId: Int64, qty: Int)`
- `getSetupProgress() throws -> WarehouseSetupProgress` — returns tier + completion %

## Files to Modify

### iOS UI
**Primary:** `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/` — new setup wizard files

Xcode prompt: `PE-030-warehouse-setup-redesign.md` (COMPLEX — will need sub-prompts)

## Test Plan
- Not required to start warehouse setup to use app ✅
- Can start Parts Flow without Floor Plan ✅
- Floor Plan: can stop at any tier, resume ✅
- Bin move with cart: moves maintain position data ✅
- Count verification passes with real part data ✅

## Priority
Medium — app is usable without it. No blocking current workflows. Plan for Phase 3.5 of iOS page rebuild.

---

## Q&A Decisions Applied (GitHub #22 — 2026-04-08)

These answers were provided by the owner and are now locked design decisions:

1. **"Assumes Row 1" confirmed as bug** — wizard pre-fills all units into Row 1 instead of leaving them unplaced for manual drag-and-drop.
2. **Dimensions-first design chosen** — user enters explicit rows × cols (e.g., 3×5) before seeing the grid. Do NOT auto-calculate from unit count.
3. **True drag-and-drop required** — tap-to-place becomes legacy. `WizardStepPlacement.swift` must be rewritten to implement iOS drag-and-drop using DragGesture/DropDelegate or `.dropDestination(for:)`.

**Xcode Prompt:** `xcode-ai/fix-prompts/PE-040-warehouse-wizard-dragdrop-placement.md`
