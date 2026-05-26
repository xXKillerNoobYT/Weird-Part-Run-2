# iOS Receiving Session — Auto-Save Draft Persistence

## What This Does (Plain English)
When a warehouse worker is receiving a shipment (scanning items and entering quantities),
any accidental Back tap, swipe-to-dismiss, or app backgrounding currently discards all
their work with no warning. This plan adds silent auto-persistence: every quantity
change is immediately written to the database, so the session can always be resumed
exactly where it left off.

## Status (2026-05-26 Docs QA)
- **Implemented:** PE-041 is complete in `IOSReceiveShipmentPage.swift`.
- **Quantity auto-save:** stepper changes, Reset to Expected, Clear All, and barcode scan increments call `updateSessionItem(itemId:receivedQty:)` in `Task {}` and surface save failures.
- **Resume behavior:** `loadSessionItems()` restores saved `receivedQty` when present and falls back to `expectedQty` for fresh sessions.
- **Related fixed findings:** T1-15 (draft loss), T2-13 (per-part receiving barcode scan), and T2-14 (default received qty) are superseded by the shipped receiving implementation.

## Why We Need This
- **Real recurring pain** (owner-confirmed): happens regularly in the field
- Workers scan dozens of items, tap back accidentally, lose everything
- Fix: make every quantity change immediately durable in the DB

## Current State
- `IOSReceiveShipmentPage.swift` holds quantities in `@State private var receivedQtys: [Int64: Int] = [:]`
- Quantity mutations now write through `WarehouseService.updateSessionItem(...)` before completion.
- A Back navigation or swipe dismissal no longer loses entered quantities because the in-progress session items are already updated.
- The old discard-confirmation approach was superseded by owner-approved silent autosave.

## Owner Decisions (Q&A #36 — 2026-04-07)
- **No confirmation dialog needed** — auto-save draft on every quantity change
- **Silent persistence** — write to DB immediately on any quantity change
- **Resume on reopen** — when user returns to an in-progress session, quantities should reload
- **App backgrounding** — persistence must also work when app backgrounds mid-session
- **Priority: HIGH** — real, recurring field problem

## Current Infrastructure (Already Exists — No Migration Needed)
- `receiving_sessions` table — session already persists with `status = 'in_progress'`
- `receiving_session_items` table — has `received_qty` column (int, default 0)
- `WarehouseService.updateReceivingItem(...)` (line ~1051) — already writes `received_qty` per item
- `WarehouseService.getSessionItems(sessionId:)` — already reads back `received_qty` per item

## Proposed Changes

### Files to Modify

#### `IOSReceiveShipmentPage.swift`
This is the only file that needs to change. Three targeted fixes:

**Fix 1: Auto-save on quantity change**
- Currently: `receivedQtys[itemId] = newQty` (state-only mutation)
- Add: immediately after updating `@State`, call `WarehouseService.updateReceivingItem()` in a `Task { }` to write the quantity to the DB
- Pattern used elsewhere (see `CartManager.swift`): wrap the DB write in `Task { try? await MainActor.run { ... } }` — but since this is a simple async write, use `Task { try? appCore.warehouseService?.updateReceivingItem(sessionId: ..., itemId: ..., qty: ...) }` via `db.writer.write`

**Fix 2: Load saved quantities on resume**
- Already called: `loadSessionItems()` loads `receivedQtys` from `getSessionItems()`
- Currently: `sessionItems.forEach { receivedQtys[$0.id] = $0.receivedQty }` — this already restores from DB!
- Verify: ensure the restore line is present. If it is, Fix 2 may already work for free once Fix 1 is in place.

**Fix 3: Remove the discard confirmation dialog**
- `showDiscardConfirmation` state variable — remove the confirmation dialog sheet/alert
- The `interactiveDismissDisabled` guard may still apply (already added via PE-037 if session is in `isCompleting` state) — keep `isCompleting` guard, but allow dismiss at all other times
- Remove the `.confirmationDialog("Discard receiving session?", ...)` and associated `showDiscardConfirmation` flag

### Data Flow (Plain English)
1. Worker opens receiving session (session `id` already in DB, `status = 'in_progress'`)
2. Worker scans or enters a quantity for item X
3. `receivedQtys[item.id] = newQty` — updates UI immediately
4. **NEW:** `Task { try? warehouseService.updateReceivingItem(sessionId:, itemId:, receivedQty:) }` — writes to DB silently
5. Worker accidentally taps Back — no dialog, session dismisses
6. Worker opens the session again from the sessions list
7. `loadSessionItems()` reads `received_qty` from DB — all quantities restored

## Files to Create
None — this is a targeted fix to one existing file.

## Test Plan
- Start a receiving session, scan 3 items with quantities
- Navigate away (Back button)
- Reopen the same session from the sessions list
- All 3 quantities should be restored
- Test: app backgrounding mid-session → foreground → reopen → quantities present

## Xcode Prompt
`xcode-ai/fix-prompts/PE-041-receiving-auto-save-draft.md`

## Security Considerations
No new security surface. All writes go through existing `WarehouseService` which uses parameterized SQL.

## Apple HIG Notes
- No confirmation dialog on Back — silently preserves state, which is the HIG-preferred pattern for autosave workflows (no "are you sure?" for data that is automatically saved)
- Resume UX: session list shows "In Progress" badge indicating resumable session (already present)
