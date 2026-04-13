# iOS Foundation Fixes — Design Plan

> **Status:** COMPLETE — Prompts 01-10 done; 35A-I cancelled (GRDB fully absent, confirmed 2026-04-12)
> **Prompts:** `xcode-ai/fix-prompts/done/` (01-10 archived); 35A-I never written (moot)
> **Last updated:** 2026-04-12 (plan-enforcer run 13)

---

## Overview

Cross-cutting fixes applied to the entire iOS app before page-by-page review began. These established the baseline quality patterns that all subsequent work follows.

## Decisions & Patterns Established

### Sheet Management (Prompt 01)
- **Single `.sheet(item:)` rule:** SwiftUI only respects the first `.sheet()` modifier. Use `ActiveSheet` enum with ONE `.sheet(item:)` per view.
- **Data reload on dismiss:** Use `.onChange` or `onSave` callback to reload data when sheet closes.
- 7 files converted, 3 fixed for missing reload.

### Error Visibility (Prompt 02)
- **Every `loadData()` must have `@State private var loadError: String?`** with UI display
- **Never just `print()` errors** — always show to user via `ContentUnavailableView` or `ErrorStateView`
- 19 files fixed across all feature areas

### Loading States (Prompt 03)
- **Guard-let-else must clear isLoading** — prevents infinite spinner on guard failure
- Every data-loading view handles 4 states: loading, error, empty, content

### Sync Honesty (Prompt 04)
- **No fake sync** — `IOSSyncManager.isSyncAvailable` returns false
- `SyncWaitingView` shows "Sync Not Available Yet" with Go Back button
- `DevicePairingView` QR disabled with clear message

### AppCore Safety (Prompt 05)
- **Safe optionals** — no IUOs (`db!`), uses `AppCoreError` enum instead of `fatalError()`
- `databasePath()` throws instead of crashing
- Auth methods guard with "App not ready" message
- No `DispatchQueue.main.asyncAfter` in auth views

### CRUD Completeness (Prompts 06-08)
- **06 — Jobs & People:** All 10 People pages have add/edit/delete CRUD. All service methods exist.
- **07 — Orders & Warehouse:** JPO detail has Add Line Item + Approve/Reject. PO detail has Receive Shipment. Procurement has Generate PO. Returns has Create Return. Audit has Start Audit.
- **08 — Scheduling & Chat:** Time-off approval works. Chat channel creation works.

### Security Hardening (Prompt 09)
- **PIN hashing:** Per-user salt with 10K iterations (was fixed salt)
- **Token generation:** `generateLocalToken` returns nil not "invalid_token"

### Service Layer Bugs (Prompt 10)
- `OrdersService` uses correct `order_status_history` table name
- `ToolsService.getToolsStats` filters active checkouts only
- `SchedulingService.createTimeOffRequest` correctly expands date range
- `ConflictResolver` + `SyncEngine` have table name whitelist (140+ tables)
- `ChangeTracker` uses safe `?? 0` unwrapping

## Cross-Cutting Rules (Apply to ALL Pages)

These rules were established by prompts 01-10 and must be followed everywhere:

| Rule | Source |
|------|--------|
| Single `.sheet(item:)` per view | Prompt 01 |
| `@State loadError` + UI display on every page | Prompt 02 |
| 44px minimum touch targets | Prompt 01 |
| No `import GRDB` in UI files — service layer only | Prompt 01, 15, 23A |
| Delete confirmation on all delete buttons | Prompt 01, 13, 14, 15 |
| Inline error feedback in forms (no `print()`) | Prompt 14D, 15B |
| Pull-to-refresh on all lists | Distributed |
| Save button disabled + spinner during save | Prompt 14D, 15B |
| Guard-let-else clears isLoading | Prompt 03 |
| No placeholder "Phase X" text | Prompt 04 |

---

*Prompts 01-10 complete — these patterns are the baseline for all future work.*

*Prompts 35A-I (GRDB removal pass) are **cancelled** — zero `import GRDB` statements exist anywhere in the iOS app as of 2026-04-12. AppCore.swift, PartsCategoriesPage.swift, and DataRefreshNotifier.swift contain only comments referencing GRDB for architectural context; no actual import or GRDB API calls remain in UI layers. The underlying objective is fully achieved.*
