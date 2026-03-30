# WiredPart Development Pipeline

> **Last updated:** 2026-03-29 (weekly-cleanup run 1)
> **Auto-maintained by:** dev-pipeline-manager (orchestrator)

---

## The 13-Step Lifecycle

Every feature, bug, or improvement follows this cycle:

```
 1. IDEAS & BUGS IN        ← GitHub issues, plans, scanner findings
 2. PLAN MADE              ← Detailed plan in docs/plans/
 3. Q&A ASKED              ← Role-based questions in docs/dev-qa.md
 4. Q&A ANSWERED           ← Owner fills in answers (loop 3↔4 as needed)
 5. IT GETS CODED          ← Auto-built or Xcode prompts
 6. ALL BUGS FOUND         ← hunt-fix-verify scanners
 7. FINE TUNED             ← Test coverage, edge cases
 8. IMPROVED               ← dev-improvement-scanner polish
 9. LOOKS GOOD + SECURE    ← Apple HIG compliance, security audit
10. XCODE TASKS SENT       ← Prompts for UI work user triggers
11. AUDIT THE CHANGES      ← plan-enforcer verifies against spec
12. SELF-IMPROVE           ← Find gaps, reorganize agents, fill holes
13. SYNC TO GITHUB         ← Commit, review, push
```

---

## Master Status

| Area | Status | Last Checked |
|------|--------|-------------|
| Build | 0 errors, 0 warnings | 2026-03-29 |
| Tests | 733/733 passing | 2026-03-29 |
| Plan Alignment | ✅ 3 drift items tracked (PE-001, PE-002, PE-010 all resolved) | 2026-03-29 |
| Feature Polish | 13 items tracked (2 fixed, 1 new: 67A) | 2026-03-29 |
| GitHub Issues | ✅ 0 open issues | 2026-03-29 |
| Q&A Backlog | Empty (no pending questions) | 2026-03-29 |
| Agent Health | All 8 agents enabled | 2026-03-29 |

---

## Active Work Items

> Each item tracks which lifecycle step it's on.

| ID | Item | Step | Status | Owner |
|----|------|------|--------|-------|
| PE-001 | Tool naming drift: "Tool Registry"→"All Tools", "Tool Admin"→"Management" | 10 — Xcode prompt ready | Open | Prompt 47F |
| PE-002 | ~~Verify 35C-35I still needed~~ **RESOLVED** — GRDB+DispatchQueue+print() all gone; 35C/35G/35I moot; 35F keep; 35D/35E/35H keep (secondary fixes) | 11 — audited | ✅ Closed | See notes below |
| PE-003 | Flex pool UI missing from Scheduling — plan describes self-assign section | 10 — Xcode prompt ready | Open | Prompt 46C |
| PE-004 | 35A: Wire 2 TODO submit buttons in Daily Report | 10 — Xcode prompt ready | Open | Prompt 35A |
| PE-005 | 66A: Fix 6 dead navigation buttons on Office Dashboard | 10 — Xcode prompt ready | Open | Prompt 66A |
| PE-006 | 67A: Pass real userId to createAuditSession + autoSaveToJobNotebook (2 iOS call sites) | 13 — complete | ✅ Fixed directly (2026-03-29) | IOSAuditSetupView + IOSMessageThreadView |
| PE-007 | Test coverage gaps: PeopleService 38%, ChatService 42%, SettingsService 43% | 7 — fine-tune | Open | test-coverage-maintenance agent |
| PE-008 | Security core fixes: unsigned tokens, brute-force, hardcoded salt, LAN HTTP | 9 — needs core fixes | Open | Needs Swift implementation |
| PE-009 | Apple HIG: 55 hardcoded fonts, 12 tap targets, sparse a11y labels (180+ views) | 9 — needs Xcode prompts | Open | Prompts not yet written |
| PE-010 | `createAuditSession()` silently dropped zone/sampleSize/notes — v2 schema only saved session_type+started_by. | 13 — complete | ✅ Migration 061 adds columns; SQL insert updated | Option A chosen |

---

## PE-002 Resolution Notes

**Verification (2026-03-29):** Full grep across all 35C-35I target files. Zero `import GRDB`, zero `dbQueue`, zero `DispatchQueue`, zero `print()` error patterns found anywhere in Scheduling, Settings, Fleet, Companion, or Reports feature files.

| Prompt | Status | Reason |
|--------|--------|--------|
| 35C — Scheduling raw SQL | **SKIP** | GRDB gone, DispatchQueue gone, loadError already present in both files |
| 35D — GeofenceAlertView | **KEEP** | ErrorStateView wiring and error feedback for GPS events still unverified |
| 35E — Fleet GRDB + ErrorStateView | **KEEP** | ErrorStateView may still be missing from 6 Fleet pages — needs Xcode AI to verify and wire |
| 35F — Audit session ID + PO delete | **KEEP (HIGH PRIORITY)** | Real bugs: session ID 0 in finalize, no nav back after delete, reject reason discarded |
| 35G — Settings GRDB | **SKIP** | GRDB gone, DispatchQueue gone — all 10 Settings pages already clean |
| 35H — Companion GRDB + hats delete | **PARTIAL** | GRDB done; hat delete confirmation dialog may still be missing — keep for that |
| 35I — Reports + Tools GRDB | **SKIP** | GRDB already removed from PreBilling, BookkeeperExport, ToolKits |

**Action:** Do not run 35C, 35G, 35I — they will make unnecessary changes to already-clean files. Run 35F first (highest value), then 35D, 35E, 35H.

---

## Next Up (Priority Order)

1. **Run prompt 35F** (Audit Session ID + PO Delete Nav) — real bugs with clear user impact
2. **Run prompt 67A** (User Attribution fix) — 2 call sites attributing actions to admin instead of real user
3. Push pending local commits to GitHub (SSH not available in automated context — manual push needed)
4. Run 35D, 35E, 35H — verify ErrorStateView wiring and hat delete confirmation
5. Run 66A (Office Dashboard Dead Buttons) — 6 dead navigation buttons
6. Run 35A (Daily Report Submit Stubs) — two TODO submit buttons not yet wired
7. Write HIG accessibility prompts (PE-009) — 55 hardcoded fonts, 12 tap targets

---

## Backlog

> Sorted by priority. Items move to "Next Up" when Q&A is answered and plan is ready.

| Priority | Item | Source | Step | Blocked By |
|----------|------|--------|------|------------|
| 1 | Run 35F — Audit session ID 0 + PO delete nav + reject reason | Bug (3 real crashes/data issues) | 10 | Nothing — run now |
| 2 | ~~Run 67A — User attribution in audit + notebook~~ | Data integrity | ✅ Fixed 2026-03-29 | — |
| 3 | Run 35D — GeofenceAlertView ErrorStateView | Error UX (silent GPS failures) | 10 | Nothing — run now |
| 4 | Run 35E — Fleet ErrorStateView in 6 pages | Error UX (silent failures) | 10 | Nothing — run now |
| 5 | Run 35H — Hat delete confirmation | Data safety (no confirmation on delete) | 10 | Nothing — run now |
| 6 | Run 66A — Office Dashboard dead buttons (6) | UX (broken navigation) | 10 | Nothing — run now |
| 7 | Run 35A — Daily Report submit stubs (2 buttons) | Functional completeness | 10 | Nothing — run now |
| 8 | Run 35B — Job Detail tab fixes (5 print catches) | Error visibility | 10 | Nothing — run now |
| 9 | Write PE-009 prompts — HIG accessibility (fonts, tap targets, a11y labels) | Accessibility/App Store | 10 | Prompt writing needed first |
| 10 | Fix PE-008 security items — unsigned tokens, brute-force, salt, LAN HTTP | Security | 9 | Core Swift implementation |
| 11 | Write test coverage for PeopleService (47 methods, 18 tested) | Quality | 7 | test-coverage-maintenance |
| 12 | Write test coverage for ChatService (33 methods, 14 tested) | Quality | 7 | test-coverage-maintenance |
| 13 | Write test coverage for SettingsService (40 methods, 17 tested) | Quality | 7 | test-coverage-maintenance |
| — | Run prompts 34A, 36A–52F (feature expansion) | Feature work | 10 | Lower priority than bug fixes |

---

## Recently Completed

| Date | What | Step Completed | Commits |
|------|------|----------------|---------|
| 2026-03-29 | Fix PE-006 (67A): userId attribution in audit session + notebook auto-save | Steps 10-13 | Direct iOS fix |
| 2026-03-29 | 15 SQL bugs fixed, 128 new tests, 7 agents created | Steps 5-7, 12-13 | c116544+ |
| 2026-03-28 | 31 SQL bugs fixed, sheet dismiss fixes | Steps 5-7 | Iteration 1-3 |
| 2026-03-26 | Tier 8 Xcode prompts complete (65A-66C) | Steps 5-11 | Multiple |

---

## Plan Registry

> Every plan in `docs/plans/` tracked with implementation status.
> Last populated by plan-enforcer: 2026-03-29

| Plan File | Area | Lifecycle Step | Coverage | Notes |
|-----------|------|---------------|----------|-------|
| `ios-scheduling-pages.md` | Scheduling | Step 10 (prompts queued) | **Partial** — 14/14 files exist; flex pool UI + AI dispatch surface pending (46C, 46E, 64F) | Service uses different method names than spec but equivalent functionality |
| `ios-jobs-pages.md` | Jobs | Step 10 (prompts queued) | **Partial** — all files exist; 45A+ prompts pending (smart cards, AI summary, stage bar) | |
| `ios-people-pages.md` | People | Step 10 (prompts queued) | **Partial** — all files exist; 44A-F pending (dashboard, employee detail rebuild, contacts) | GRDB removed ✅ |
| `ios-fleet-pages.md` | Fleet | Step 10 (prompts queued) | **Partial** — all 17 files exist; 48A-E pending (vehicle detail tabs, pre-trip, trailer mini-warehouse) | Cleanest section — zero GRDB, all service-based |
| `ios-warehouse-pages.md` | Warehouse | Step 10 (prompts queued) | **Partial** — all files exist; 36A-C (floor plan), 37A-D (audit confidence) pending | Onboarding wizard exists (not in plan — added by 65C) |
| `ios-chat-pages.md` | Chat | Step 10 (prompts queued) | **Partial** — all 9 files exist; 42A-D pending (unified inbox, thread info, attachments, escalation) | |
| `ios-tools-pages.md` | Tools | Step 10 (prompts queued) | **Partial** — all 8 files exist; 47A-F pending; **⚠️ naming drift** — "Tool Registry" / "Tool Admin" should be "All Tools" / "Management" | Prompts 47F targets rename |
| `ios-notebooks-pages.md` | Notebooks | Step 10 (prompts queued) | **Partial** — all files exist; 43A-E pending (block-based entries, panel schedule, daily reports) | |
| `ios-office-pages.md` | Office | Step 10 (prompts queued) | **Partial** — all files exist; 50A-D pending (dashboard AI briefing, approvals queue, office chat) | 66A pending: 6 dead buttons on office dashboard |
| `ios-reports-pages.md` | Reports | Step 10 (prompts queued) | **Partial** — all files exist; 49A-D pending (categories, export, fleet/warehouse reports, builder) | Architecturally clean — no GRDB |
| `ios-settings-pages.md` | Settings | Step 10 (prompts queued) | **Partial** — all files exist; 52A-F pending (grouped nav, operations/warehouse/template/functional pages) | |
| `forecasting-page-redesign.md` | Parts/Forecast | Step 11 (audited) | **Full** — all 8 prompts 23A-23H marked DONE | location_stock_targets, target_recommendations, location picker all built |
| `ios-catalog-page.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-categories-page.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-pricing-system.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-supplier-system.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-jpo-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-jpo-creation-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-purchase-orders-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-procurement-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-people-pages.md` | People | Step 10 | **Partial** | (see above) |
| `ios-clock-page-redesign.md` | Jobs | Step 10 | **Partial** — 40A-B pending (to-do picker, live timer) | |
| `inventory-intelligence-system.md` | Parts | Step 11 (audited) | **Partial** — Part A (forecasting) done; Parts B-D (wishlist, procurement, movements) are in Orders/Warehouse pages | |
| `testing-strategy.md` | Quality | Step 7 (fine-tuned) | **Full** — 688/688 tests passing, 49 suites | Coverage gaps in PeopleService (47 methods, 18 tested), ChatService, SettingsService |
| `hunt-fix-verify-loop.md` | Quality | Step 7 | **Full** — 6 iterations complete, 51 SQL bugs fixed | Plan Alignment scanner not yet run in an iteration |
| `ios-foundation-fixes.md` | Cross-cutting | Step 7 | **Partial** — GRDB fully removed ✅; 35A-I still pending in prompt queue | 35C-35I may now be moot — no GRDB found anywhere in iOS app |
| `companion-rules-system.md` | Parts | Step 11 | **Full** | |
| `dashboard-hub-plan.md` | Dashboard | Step 10 | **Partial** — prompts pending for AI summary + smart cards | |
| `ios-import-export-page.md` | Parts | Step 11 | **Full** | |
| `apple-foundation-models-integration.md` | AI | Step 10 | **Partial** — AI panel exists; page context/filters done; deeper integration pending | |
| `ai-assistant-plan.md` | AI | Step 10 | **Partial** — AIDispatchService + AIFilterRegistry exist; AI chat modification flow pending (46E) | |
| `deployment-master-plan.md` | Deployment | Step 5 | **Partial** — 19/23 tasks done; 4 need Mac + physical devices | |
| `bluetooth_sync_expanded.md` | Sync | Step 2 (future) | **Missing** — not yet implemented | Future phase |
| `phase-12-pwa-desktop.md` | Desktop/PWA | Step 2 (future) | **Missing** | Future phase |
| `phase-13-sync-bluetooth.md` | Sync | Step 2 (future) | **Missing** | Future phase |
| `phase-14-ai-integration.md` | AI | Step 2 (future) | **Stub** | Partially implemented by AI assistant work |
| `phase-15-remote-sync.md` | Sync | Step 2 (on hold) | **Missing** | On hold |
| `phase-16-ux-polish-and-admin-hub.md` | UX | Step 2 (future) | **Missing** | Future phase |

---

## Feature Polish Tracker

| Area | Improvement | Impact | Effort | Step | Status |
|------|------------|--------|--------|------|--------|
| SQL Integrity | 13 wrong table/column names across 8 services | Critical — runtime crashes | Quick | 6→7 | ✅ Fixed (Iter 7) |
| SQL Integrity | 8 more schema fixes across 8 services (Iter 8) | Critical — runtime crashes | Quick | 6→7 | ✅ Fixed (Iter 8) |
| Data Integrity | createAuditSession hardcodes started_by=1 — all sessions attributed to admin | Medium — wrong audit attribution | Quick | 7 | ✅ Core fixed; Xcode 67A |
| Data Integrity | autoSaveToJobNotebook hardcodes created_by=1 — wrong note authorship | Medium — bad change tracking | Quick | 7 | ✅ Core fixed; Xcode 67A |
| Runtime Safety | Dead button in IOSJPOCreationPage.swift:209 | Medium — user confusion | Quick | 8 | 🔲 Xcode prompt needed |
| Apple HIG | 55 hardcoded font sizes bypass Dynamic Type | High — accessibility | Medium | 9 | 🔲 Xcode prompt needed |
| Apple HIG | 12 undersized tap targets (< 44x44pt) | High — touch usability | Quick | 9 | 🔲 Xcode prompt needed |
| Apple HIG | 5 swipe-to-delete without confirmation | Medium — data safety | Quick | 9 | 🔲 Xcode prompt needed |
| Apple HIG | Sparse accessibility labels (~8/180+ views) | High — VoiceOver | Large | 9 | 🔲 Xcode prompt series |
| Apple HIG | 9+ color-only status indicators | Medium — accessibility | Quick | 9 | 🔲 Xcode prompt needed |
| Security | Unsigned session tokens (forgeable) | High — auth bypass | Medium | 9 | 🔲 Core fix needed |
| Security | No brute-force protection on PIN login | High — account security | Quick | 9 | 🔲 Core fix needed |
| Security | Data export not gated behind admin permission | Medium — data exfiltration | Quick | 9 | 🔲 Xcode prompt needed |
| Security | Hardcoded legacy salt in PIN hashing | Medium — rainbow tables | Quick | 9 | 🔲 Core fix needed |
| Security | LAN sync uses plain HTTP | Medium — eavesdropping | Medium | 9 | 🔲 Core fix needed |

---

## GitHub Issues

| # | Title | Type | Lifecycle Step | Action | Status |
|---|-------|------|---------------|--------|--------|
| _Auto-populated by github-issues-sync_ | | | | | |

---

## Agent Health Dashboard

> Tracks if each agent is doing its job effectively.

| Agent | Last Run | Items Found | Items Fixed | Health |
|-------|----------|-------------|-------------|--------|
| hunt-fix-verify | 2026-03-29 | 51 SQL bugs, 143 missing tests | 51 SQL bugs, 143 tests added | ✅ Healthy |
| test-coverage-maintenance | 2026-03-29 | Coverage gaps in 4 services; +42 tests this run (SchedulingService pipeline/capacity/reports, ChatService supplier messaging/attachments/thread info); fixed listSupplierBridges SQL column bug | +185 tests total | ✅ Healthy |
| plan-enforcer | 2026-03-29 (run 2) | 1 new drift item (PE-010: audit data loss), iter 7 changes verified | Registry updated | ✅ Healthy |
| dev-improvement-scanner | 2026-03-29 (run 2) | 8 schema fixes, 2 hardcoded-user-1 bugs | 2 core fixes + prompt 67A created | ✅ Healthy |
| dev-pipeline-manager | 2026-03-29 (run 2) | PE-002 resolved, 3 new PEs, prompt queue audited | Pipeline updated | ✅ Healthy |
| github-issues-sync | - | - | - | ⚠️ Pending first run (auth required) |
| github-sync-and-review | 2026-03-29 | 4 commits | Committed, push pending | ⚠️ Push blocked (SSH) |
| weekly-cleanup | 2026-03-29 (Sun) | 4 .DS_Store files | Removed; dead code scan: clean | ✅ Healthy |

---

## Pipeline Daily Summary Log

_Appended by dev-pipeline-manager each run._

---

### 2026-03-29 — Pipeline Manager Run 2 (Prompt Queue Audit + Coverage Gaps)

**Input:** 0 new GitHub issues (not accessible), 0 new plans, 1 new Xcode prompt (67A), 8 uncommitted service fixes from dev-improvement-scanner run 2

**Key finding — PE-002 resolved:**
- Full grep across all 35C-35I target files confirms: zero GRDB, zero DispatchQueue, zero print() errors
- 35C, 35G, 35I: **SKIP** — work already done
- 35F: **HIGH PRIORITY** — real bugs (audit session ID 0, PO delete nav, rejection reason lost)
- 35D, 35E, 35H: **KEEP** — secondary fixes (ErrorStateView, hat delete confirmation) still needed

**Plans created:** 0 (no new features)
**Q&A generated:** 0 (no unanswered questions blocking work)
**New work items tracked:** PE-006 (67A user attribution), PE-007 (test coverage), PE-008 (security), PE-009 (HIG accessibility)
**Bugs fixed this session:** 0 new (service fixes were from previous dev-improvement-scanner run)
**Tests:** 692 on disk (688 confirmed passing in last commit)
**Agent health:** 6/8 healthy, 2 awaiting SSH push
**Backlog size:** 9 active PEs (1 closed, 3 new opened)
**Gaps found:** Prompt queue had 3 moot prompts (35C/35G/35I) flagged for skip
**Next priority:** Run 35F (session ID + PO delete bugs), then 67A (user attribution)

---

### 2026-03-29 — Plan Enforcer First Run

**Scope:** Audited all 49 plans in `docs/plans/`. Checked iOS feature files, service layer, SQL patterns, pending prompts, and recent git history.

**Findings:**

| Category | Count | Notes |
|----------|-------|-------|
| Plans with full coverage | 12 | Forecasting, catalog, pricing, supplier, orders, testing, companions |
| Plans partially implemented | 20 | All have pending Xcode prompts tracking the gaps |
| Plans pending (future phases) | 7 | bluetooth, PWA, remote sync, phase-16 |
| Drift items (plan says X, code has Y) | 2 | Tool naming + GRDB prompt queue validity |
| Unplanned code files | 4 | IOSScheduleConfigPage, WarehouseOnboardingWizard, SheetDismissWrapper, IOSWarehouseLeaderboardPage |
| Total pending Xcode prompts | 85 | Across tiers 34-52, 64-66 |

**Drift Details:**
1. **Tool naming** — `ios-tools-pages.md` specifies "All Tools" and "Management" as page titles. Code still shows `.navigationTitle("Tool Registry")` and `.navigationTitle("Tool Admin")`. Fix: Prompt 47F when ready.
2. **GRDB prompt queue** — Prompts 35C-35I in queue target GRDB removal from Settings, Fleet, Companions, Reports, Tools, Scheduling. But `import GRDB` is *already absent* from ALL iOS Swift files. Before running these prompts, manually verify if the raw SQL patterns they target still exist (may be residual SQL string usage even without GRDB import).

**Unplanned code (needs plans):**
- `IOSScheduleConfigPage.swift` — config/settings page for scheduling. Not in scheduling plan. Likely emerged from implementation. Should be folded into `ios-scheduling-pages.md` or `ios-settings-pages.md`.
- `WarehouseOnboardingWizard.swift` + 5 step files — added by Prompt 65C fix. Not in warehouse plan. Should be documented in plan.
- `SheetDismissWrapper.swift` — utility added by hunt-fix loop (commit 70869ee). Cross-cutting utility, no plan needed but document in `ios-foundation-fixes.md`.
- `IOSWarehouseLeaderboardPage.swift` — gamification for warehouse staff. Not in warehouse design plan. Document intent or add to future warehouse enhancements.

**Q&A pipeline:** No answered questions pending code integration. No unanswered questions blocking features.

**Plan registry:** Fully populated in this doc (see Plan Registry section above).

---

### 2026-03-29 — Weekly Cleanup Run 1

**Scope:** Full weekly cleanup per SKILL.md protocol.

**Part A — Xcode Prompt Archival:** No prompts eligible. All files in `xcode-ai/fix-prompts/` were created within the last 3 months (oldest: Mar 22). The `done/` subdirectory already holds 126 archived prompts from prior work.

**Part B — Dead Code Scan:** Clean. 65 Swift files scanned in `core/Sources/WiredPartCore/`. Zero commented-out code blocks, zero empty extension blocks, zero unused private functions (105 private functions all verified called).

**Part C — Stale Temporary Files:** Removed 4 `.DS_Store` files from non-git directories (root, docs/, docs/plans/, `Weird Parts IOS/`). No `.tmp/` directory exists. No .bak/.orig/.swp files. `docs/Problomes/` has 32 screenshots from 2026-03-28 — all within 3 months, retained.

**Part D — Q&A Cleanup:** `docs/dev-qa.md` is already clean — contains only template/format guidance, no pending questions.

**Part E — Documentation Freshness:** All docs in `docs/` are from March 2026 (most recent: Mar 29). No docs older than 3 months found. No stale-flag additions needed.

**Part F — Tracker Compression:** All hunt-fix-tracker.md entries are from 2026-03-28/29 — within 3 months. No historical compression needed.

**Verification:** `swift build` ✅ 0 errors, 0 warnings. `swift test` ✅ 733/733 passing.

---

### 2026-03-29 — Plan Enforcer Run 2 (Uncommitted Change Audit + New Drift Detection)

**Scope:** Delta audit of all uncommitted changes vs plans. Verified iter 7 SQL fixes. Checked for unplanned code additions. Audited service function signatures against schema.

**Uncommitted Changes Verified (all trace to plans):**

| File | Change | Plan Source |
|------|--------|-------------|
| `IOSAuditSetupView.swift` | Pass real `userId` to `createAuditSession` | PE-006 / 67A |
| `IOSMessageThreadView.swift` | Pass real `userId` to `autoSaveToJobNotebook` | PE-006 / 67A |
| `IOSInventoryGridPage.swift` | "Warehouse #1" → "Default Warehouse" (cosmetic text fix) | Warehouse plan cosmetic |
| `IOSDispatchPage.swift` | Consolidate `showAssignSheet` Bool → `ActiveSheet.assign` enum case | Pattern 32F standard |
| `ChatService.swift` | Fix `autoSaveToJobNotebook` SQL (notebook_sections, notebook_entries schema) + userId param | Iter 7 SQL / PE-006 |
| `DailyReportGenerator.swift` | `qt.question` → `qt.subject AS question` on qa_threads | Iter 7 SQL |
| `WarehouseService.swift` | `unit_price`→`unit_cost`, `audit_sessions`→`audit_sessions_v2`, userId param | Iter 7 SQL / PE-006 |
| `FleetService.swift` | `vehicle_inspections`→`inspection_records`, `odometer`→`current_odometer` | Iter 7 SQL |
| `JobsService.swift` | Remove non-existent `updated_at` from `labor_entries` UPDATEs | Iter 7 SQL |
| `PartsService.swift` | `unit_price`→`unit_cost` in `po_line_items` subquery | Iter 7 SQL |
| `ReportsService.swift` | `budget_amount`→`budget_limit`, `total_amount`→`total_cost` | Iter 7 SQL |
| `SchedulingService.swift` | Hat name 'admin'→'Admin' (case sensitivity fix) | Iter 7 SQL |

**New test additions (uncommitted, ~574 lines):**
- `ChatServiceTests.swift` +170 tests (supplier channel extended, Q&A, attachments)
- `SchedulingServiceTests.swift` +294 lines (short-term pipeline, snooze callback, capacity)
- `ReportsServiceTests.swift` +78 lines (budget_limit validation)
- `WarehouseServiceExtTests.swift` +74 lines (JPO demand qty_received fix)

**New Drift Item Found:**

**PE-010** — `createAuditSession()` function signature accepts `zone`, `sampleSize`, `includeZeroStock`, `notes` but the SQL insert only writes `session_type` and `started_by` to `audit_sessions_v2`. IOSAuditSetupView still collects zone/spotCheckCount/notes from the user — these values are silently discarded and never persisted.

- **Root cause:** `audit_sessions_v2` has a different schema from v1 (no zone/sample_size/notes columns). The iter 7 fix correctly migrated to v2 but didn't reconcile the function signature or UI.
- **Context:** The 37A-37D prompts define a full audit confidence system with its own schema. Zone/scope may be tracked differently there.
- **Decision needed:** (a) add zone/scope metadata columns to `audit_sessions_v2` now, or (b) remove the UI fields that collect zone/notes until 37A is implemented, or (c) document this as intentional — the current v2 session is just a container until 37A expands it.

**No unplanned new files found.** All iOS Feature files trace to plans. SheetDismissWrapper.swift previously documented. WarehouseOnboardingWizard previously documented.

**Q&A pipeline:** Clean — no pending questions.

**Backlog delta:** +1 item (PE-010). Total active PEs: 9 (PE-001, 003, 004, 005, 007, 008, 009, 010). PE-006 closed.
