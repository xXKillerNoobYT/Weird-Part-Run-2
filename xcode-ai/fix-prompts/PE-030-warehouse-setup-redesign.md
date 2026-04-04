# PE-030 — Warehouse Setup Redesign (Optional, Progressive, Two Flows)

**GitHub Issue:** #49
**Plan:** `docs/plans/ios-warehouse-setup-redesign.md`
**Priority:** High — current wizard is too pushy, blocks app usage, and doesn't complete properly

---

## Context

The warehouse setup wizard forces users through setup before using the app, assigns everything to "Row 1" without detail, and has incomplete steps 2-6. This redesign makes setup **optional**, **progressive** (stop/resume anytime), and detailed enough to map a real warehouse.

The existing `65C-warehouse-setup-fix.md` prompt addressed the wizard steps being broken. This prompt focuses on making setup **non-mandatory** and implementing the **two independent flows** the owner defined.

---

## Owner Decisions (from Q&A)

- **Optional** — Clock In, view parts, and process orders all work WITHOUT warehouse setup
- **Two independent flows that work together (but not required together):**
  - **Parts Flow:** Parts list → count each part → assign location (works standalone)
  - **Warehouse Floor Plan Flow:** Size → Zones → Units → Placement (drag-and-drop) → Shelves → Areas → Bin types → Bin numbers → Part assignment → Count verification
- **Visual drag-and-drop** for placing units on floor plan
- **Menu-based** for detailed work (bin numbers, areas on shelves)
- **Cart/holding mode** for moving multiple bins/parts at once
- **Resumable at any step** — save progress, don't rush
- **Bins** are small boxes on shelves, NOT location-locked — can be moved, identified by bin number

---

## Task 1 — Remove the Forced Setup Gate

**File:** Look in `IOSAppRoot.swift`, `IOSCompanySetupWizard.swift`, `AppState.swift` (or equivalent)

Find where warehouse setup is made mandatory (a check that prevents navigation until setup is complete).

Change: warehouse setup should be **optional**. The app root should:
1. Let users proceed to the full app even if warehouse setup is not complete
2. Show a **dismissable banner** on the Warehouse Dashboard if setup is not done:
   `"Warehouse not configured — your parts won't have accurate locations. [Set up now]"`
3. Do NOT block navigation to Clock, Parts, Orders, or any non-warehouse page

---

## Task 2 — Parts Flow (Standalone)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseSetupPage.swift` (or similar)

Add a "Parts-First Setup" flow accessible from:
- Warehouse Dashboard banner
- Settings → Warehouse Setup → "Parts Setup"

**Parts Flow Steps:**
1. **Parts List** — show all parts from catalog; parts can be assigned a free-text location even before a full floor plan exists (e.g., "Shelf A", "Back wall")
2. **Count Entry** — for each part, enter current count (this is the physical inventory count)
3. **Location Assignment** — assign to a location (either free-text OR a bin/area from the floor plan if configured)

This flow works even with no floor plan — location is just free text until the floor plan is built.

---

## Task 3 — Warehouse Floor Plan Flow (Visual + Menu)

The existing wizard (65C) has 6 steps. This task upgrades them to match the owner's full spec:

**Step 1: Define Warehouse Size** — width × length (feet/meters), optional height
**Step 2: Define Zones** — draw/label zones on a grid:
  - Zone types: staging, storage, receiving, returns, office, tool storage, custom
  - Use a simple grid-tap UI (not pixel-perfect, just row/column selection within the warehouse area)

**Step 3: Define Storage Units** — for each zone, add units:
  - Types: shelf rack, bin rack, pallet position, work bench, cabinet, custom
  - Properties: name, dimensions, unit type

**Step 4: Place Units on Floor Plan** — **Visual drag-and-drop**:
  - Display a simplified floor plan grid showing the defined zones
  - Drag storage units onto zone grid cells
  - CRITICAL: Record row + column within zone as the unit's address
  - Units can be repositioned later

**Step 5: Define Shelves** — for each unit, add shelves (or levels):
  - Shelf name/number, height (optional)

**Step 6: Define Areas on Shelves** — sections within a shelf:
  - Area name (e.g., "Left", "Center", "Bin section")
  - Storage type: open storage (multiple parts) or bins (individual boxes)

**Step 7: Bin Numbers** — for bin areas:
  - Number of bins in this area
  - System auto-assigns bin numbers (e.g., A-001, A-002…) — user can rename
  - Bins are NOT location-locked: they can be moved at any time

**Step 8: Part Assignment** — assign catalog parts to bins or open areas:
  - For bins: assign specific part to bin
  - For open areas: assign multiple parts (list)

**Step 9: Count Verification** — confirm physical counts for all assigned parts

---

## Task 4 — Cart / Holding Mode

Add a **Cart** concept for moving multiple items:

1. On any bin/part list, user can tap "Add to Cart" on multiple items
2. Cart indicator (badge) in nav shows how many items are in the cart
3. Tapping Cart → shows items in the cart
4. "Place Cart" → for each item, select:
   - Which shelf
   - Which row/area
   - (Clears the item from cart and updates its location)

Implement as a `@StateObject CartManager` with `@Published var items: [CartItem]`.

---

## Task 5 — Progressive Save / Resume

Every step should auto-save progress to UserDefaults (or a setup progress table):
- Track which steps are complete per warehouse
- When user returns to setup, start from the last incomplete step
- Show progress bar at top: "Step 4 of 9 — Unit Placement"

---

## Verification Checklist

- [ ] App loads fully without warehouse setup (Clock, Parts, Orders accessible)
- [ ] Warehouse Dashboard shows dismissable "not configured" banner if setup incomplete
- [ ] Parts Flow: can assign location to parts without floor plan
- [ ] Floor Plan: size → zones → units → placement (drag-and-drop)
- [ ] Shelves → Areas → Bins flow all functional
- [ ] Cart mode: add multiple bins to cart, then place to location
- [ ] Progress saves on exit, resumes where left off
- [ ] Setup is accessible from Settings → Warehouse Setup at any time
- [ ] Build: 0 errors, 0 warnings
