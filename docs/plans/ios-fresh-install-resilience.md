# iOS Fresh Install Resilience Plan

## What This Does (Plain English)
On a brand-new install with an empty database, 10+ pages crash with "Something went wrong". This plan makes every page gracefully handle an empty database — showing empty states and helpful guides instead of errors.

## Why We Need This
The app is unusable out of the box. First-launch testing is blocked. New companies can't start using the app without hitting errors on almost every page.

## Current State
- `isTableNotFoundError()` helper exists in most services — handles "no such table" errors
- Most service array-returning methods have `isTableNotFoundError → []` guards
- Some service methods do NOT have this guard (found: `getTodaysClockEntries`, others likely missing)
- Empty-result crashes are different: migrations ran, tables exist, but no rows yet — service code tries to read data that doesn't exist and crashes

## Owner Decisions Applied
- **Browse first, setup later** — users can browse any page even before setup; empty states shown
- **Gated pages** — pages that literally can't function without setup (e.g., Warehouse receiving without warehouse configured) should be locked with a clear "Setup required" prompt and link to the setup wizard
- **Re-runnable onboarding guide** — setup guide accessible from Help menu, can be re-run anytime to change company settings
- **Scope of fix** — BOTH list methods (return `[]`) AND single-item fetches (return `nil`) — full fixing
- **Locked pages** should show: what needs to be done, a button to go do it, and progress (e.g., "Warehouse not configured yet — tap to set up your warehouse")

## Progressive Setup Tiers (Warehouse Example)
The owner described a tiered progressive setup:
1. Parts list (standalone, no warehouse needed)
2. Part counts per part
3. Location assignment (connects parts + warehouse)

Warehouse Floor Plan:
1. Define size
2. Define areas/zones (staging, storage, returns, etc.) + zone types
3. Define storage units within zones
4. Place units on floor plan (visual drag-and-drop)
5. Define shelves/rows per unit
6. Define areas on each shelf
7. Define what's stored in each area (kits, tools, parts, supplies)
8. If parts: open storage or bins
9. If bins: bin count + bin numbers
10. Add parts from catalog to bins/areas
11. Verify counts

**Key**: User can stop at any step and resume. Each page that requires a setup level should check if that level is complete.

## Files to Audit and Fix

### Core Service Methods Missing Guards
**Priority 1 — Clock page crash (emergency):**
- `JobsService.getTodaysClockEntries(userId:)` — add `isTableNotFoundError → return []`
- `JobsService.listLaborEntries(...)` — verify/add guard
- `JobsService.listActiveJobsForClock()` — verify/add guard

**Priority 2 — All other services:**
Run systematic audit of all `db.writer.read { }` blocks in:
- `SchedulingService.swift`
- `DashboardService.swift`
- `PeopleService.swift`
- `FleetService.swift`
- `WarehouseService.swift`
- `OrdersService.swift`
- `ReportsService.swift`
- `ChatService.swift`
- `ToolsService.swift`
- `NotebooksService.swift`

Check every method that does NOT already have `isTableNotFoundError` or `isColumnNotFoundError` guard.

### iOS Page Empty States
Every page must have a proper empty state (no crash, no error banner, helpful message):

| Page | Empty State Message | Setup Button |
|------|---------------------|--------------|
| Dashboard | "Welcome! No data yet — start by adding jobs and employees." | — |
| Clock | "No jobs to clock into — add your first job to get started." | → Jobs |
| Jobs | "No jobs yet — tap + to create your first job." | — |
| Parts Catalog | "No parts yet — tap + to add your first part." | — |
| Warehouse | "Warehouse not configured — tap to start warehouse setup." | → Setup Wizard |
| Reports | "No data yet — reports will appear after you start tracking jobs." | — |
| People | "No employees yet — tap + to add your first employee." | — |
| Orders | "No orders yet — orders appear when you create jobs that need parts." | — |
| Schedule | "No schedule entries — dispatchers can assign jobs here." | — |
| Tools | "No tools registered — tap + to add tools." | — |
| Fleet | "No vehicles yet — tap + to add your first vehicle." | — |
| Chat | "No threads yet — start a conversation from a job." | — |

## Onboarding Guide
A re-runnable setup guide should walk through:
1. Company info (name, address, time zone, state code for labor law)
2. Add first user / admin account
3. Add job categories
4. Add employee roles (hats)
5. Optional: Warehouse setup (can skip, come back later)
6. Optional: Parts catalog seed (can skip)
7. Done → launch app with appropriate empty states

**Access:** Shown on first launch AND accessible via Settings → Help → "Run Setup Guide Again"

## How It Links to Other Features
- Connects to #20 (Clock fix) — clock page crash on fresh install is a subset of this
- Connects to #49 (Warehouse Setup redesign) — progressive tier setup is part of this
- Onboarding guide is a NEW feature — needs separate Xcode prompt once this plan is approved

## Test Plan
1. Delete app, fresh install on simulator — navigate to every page — verify no crash
2. Verify every page shows appropriate empty state
3. Check Warehouse page shows "setup required" gating
4. Run setup guide, complete all steps — verify pages unlock
5. Add 1 job — verify Clock page shows it in list

## Security Considerations
- No new auth changes needed
- Empty states should still respect hat-based permissions (gated pages stay gated even when empty)
