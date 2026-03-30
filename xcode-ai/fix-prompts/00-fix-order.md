# Fix Prompt Order — WiredPart iOS Phase 2

> **Phase 1 complete.** All 279 prompts (01–67A) are archived in `done/`.
> Build: 0 errors, 0 warnings. Tests: 733/733 passing.
> This file tracks Phase 2 work: HIG polish, security hardening, and remaining PE items.

---

## How to Use

1. Pick the next prompt from the queue below
2. Paste the prompt file contents into Xcode AI
3. Run it, verify the result
4. Mark it DONE here and move the file to `done/`

---

## Queue

| # | File | What It Fixes | Status |
|---|------|---------------|--------|
| PE-001 | *(write prompt)* | Tool page rename: "Tool Registry" → "All Tools", "Tool Admin" → "Management" | ⬜ needs prompt |
| PE-003 | *(write prompt)* | Flex pool self-assign on Scheduling page (plan-enforcer finding) | ⬜ needs prompt |
| PE-009a | *(write prompt)* | HIG: 88 hardcoded font sizes across 51 files → Dynamic Type | ⬜ needs prompt |
| PE-009b | *(write prompt)* | HIG: 12 undersized tap targets (< 44×44pt) | ⬜ needs prompt |
| PE-009c | *(write prompt)* | HIG: 6 remaining swipe-to-delete without confirmation (IOSReportsRouter ✅ fixed in 4b0c71a; remaining: IOSPreTripChecklistPage, IOSClockOutQuestionsPage, IOSReportTemplatesPage ×2, WarehouseWizardStep2, AddNotebookEntrySheet) | ⬜ needs prompt |
| PE-009d | *(write prompt)* | HIG: 9+ color-only status indicators | ⬜ needs prompt |
| PE-009e | *(write prompt series)* | Accessibility labels — ~8 set across 180+ views | ⬜ needs prompt |
| PE-011 | *(closed)* | 12 force unwraps in `ReportDateRange.swift` — fixed in commit 4b0c71a | ✅ closed |
| PE-012 | *(closed)* | `Calendar.current.date(byAdding:)!` in 15 files — fixed in commit 4b0c71a (all 15 files updated) | ✅ closed |

---

## Security (Core Swift — not Xcode AI)

These require changes in `core/Sources/WiredPartCore/` — write and test directly, don't use Xcode AI:

| # | What | Severity |
|---|------|----------|
| PE-008a | Unsigned session tokens (forgeable) | High |
| PE-008b | No brute-force protection on PIN login | High |
| PE-008c | Hardcoded legacy salt in PIN hashing | Medium |
| PE-008d | LAN sync uses plain HTTP | Medium |
| PE-008e | ~~Data export not gated behind admin permission~~ | ✅ **Fixed** (4b0c71a) — IOSDataExportPage now checks `export_reports` permission |

---

## Phase 1 Archive

279 prompt files archived in `done/`. Covers everything from sheet dismiss (01) through user attribution (67A).
