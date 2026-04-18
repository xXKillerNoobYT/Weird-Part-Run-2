# Cross-Platform QA Scanner

> **Part of:** AUTO GO unified loop (see `auto-go-unified-loop.md`)
> **SKILL.md:** `~/.claude/scheduled-tasks/cross-platform-qa/SKILL.md`

## What This Does (Plain English)

WiredPart runs on iOS (SwiftUI — `Weird Parts IOS/`), and Tauri desktop macOS + Windows + Tauri mobile iOS (React — `src/`). This scanner spot-checks that a feature behaves the same on both sides, or that a deliberate platform-only feature is correctly gated.

## Why We Need This

Two codebases implement the same app. Features can drift silently: the iOS native app gets a polish pass that the React/Tauri side misses, or a bug fix lands on one platform only. Users switching between devices hit inconsistencies.

## Current State

- iOS: `Weird Parts IOS/Weird Parts IOS/Features/` — 14 modules, 100+ SwiftUI pages.
- React/Tauri: `src/` — 87 functional pages, shared 35-service TS data layer.
- Shared Swift core: `core/Sources/WiredPartCore/` — used by iOS native.
- Tauri backend: `src-tauri/` — Rust native shell.
- `docs/plans/frontend-to-root-restructure.md` notes cross-platform rules (shared `isDesktop()`/`isMobile()`, DB path config).

## Proposed Changes

### SKILL.md content

**Phase A — Pick a feature**
Read `docs/cross-platform-qa-tracker.md` to find the next feature in rotation. If empty or all covered, pick 3 random features from the cross-reference list:

| iOS module | React page | Core service |
|---|---|---|
| Parts | PartsCatalogPage | PartsService |
| Jobs | JobsPage | JobsService |
| Warehouse | WarehouseDashboard | WarehouseService |
| Scheduling | SchedulingPage | SchedulingService |
| Orders | OrdersPage | OrdersService |
| People | PeoplePage | PeopleService |
| Tools | ToolsPage | ToolsService |
| Inventory | InventoryPage | InventoryService |
| ... (14 total) | | |

**Phase B — Parity check**
For the chosen feature, verify:
1. **Service method signatures match.** Read the iOS version (`Weird Parts IOS/.../Features/{module}/*.swift`) and the React version (`src/.../{module}/*.tsx`). Both should call the same service-level verbs (create, read, update, delete, search, filter).
2. **Visible actions are identical.** List the buttons/links on the iOS page and the React page. Any action present on one but not the other is a gap.
3. **Data fields are identical.** Compare form fields, list columns, detail-view labels. Platform-specific fields (e.g., "Taken with camera" on iOS only) must be explicitly gated in both codebases.
4. **Empty/loading/error states exist on both.**

**Phase C — Responsive check (React side only)**
For the chosen React page: read its JSX and confirm tailwind breakpoints (`sm:`, `md:`, `lg:`) are used. If the page has no responsive prefixes, flag for dev-improvement-scanner.

**Phase D — File findings**
- Each parity gap → GitHub issue with label `cross-platform-parity` (check duplicates).
- Each confirmed match → logged to `docs/cross-platform-qa-tracker.md` with timestamp.
- Heartbeat logs "cross-platform-qa: feature X checked, N gaps".

## Files to Create

- `~/.claude/scheduled-tasks/cross-platform-qa/SKILL.md`
- `docs/cross-platform-qa-tracker.md` (seeded on first run)

## Test Plan

1. First run: picks 3 random features, writes tracker with initial findings.
2. Subsequent runs: pick from rotation, skip features checked in last 7 days.

## User Roles Affected

- **Developer:** gets a steady stream of "iOS has X, React doesn't" findings to address.
- **Owner:** sees parity metrics — "X of 14 modules fully cross-platform-verified this week".

## Security Considerations

N/A (read-only scan).

## Apple HIG Notes

N/A.
