# WiredPart Development Pipeline

> **Last updated:** 2026-03-29 (dev-pipeline-manager run 3 — Phase 1 complete, Phase 2 begin)
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
| Plan Alignment | ✅ All Phase 1 work aligned. 2 new unplanned features documented (warehouse drag-drop, nav path) | 2026-03-29 |
| Feature Polish | 20 items tracked (PE-011 ✅, PE-012 ✅, PE-008e ✅ fixed since last run) | 2026-03-29 |
| Xcode Prompts | **Phase 1 COMPLETE** — 279 prompts archived. Phase 2 queue: 8 items needing prompt writing | 2026-03-29 |
| GitHub Issues | ✅ 0 open issues | 2026-03-29 |
| Q&A Backlog | Empty (no pending questions) | 2026-03-29 |
| Agent Health | All 8 agents enabled | 2026-03-29 |

---

## Active Work Items

> Each item tracks which lifecycle step it's on.

| ID | Item | Step | Status | Owner |
|----|------|------|--------|-------|
| PE-001 | Tool naming drift: "Tool Registry"→"All Tools", "Tool Admin"→"Management" | 10 — Phase 2 prompt needed | Open | Write new prompt |
| PE-002 | ~~Verify 35C-35I still needed~~ **RESOLVED** | 13 — complete | ✅ Closed | All prompts run or skipped |
| PE-003 | Flex pool UI missing from Scheduling — plan describes self-assign section | 10 — Phase 2 prompt needed | Open | Write new prompt |
| PE-004 | ~~Wire 2 TODO submit buttons in Daily Report (35A)~~ | 13 — complete | ✅ Closed — 35A archived 2026-03-29 | — |
| PE-005 | ~~Fix 6 dead navigation buttons on Office Dashboard (66A)~~ | 13 — complete | ✅ Closed — 66A already complete; archived 2026-03-29 | — |
| PE-006 | 67A: Pass real userId to createAuditSession + autoSaveToJobNotebook | 13 — complete | ✅ Fixed directly (2026-03-29) | IOSAuditSetupView + IOSMessageThreadView |
| PE-007 | Test coverage gaps: PeopleService 38%, ChatService 42%, SettingsService 43% | 7 — fine-tune | Open | test-coverage-maintenance agent |
| PE-008 | Security core fixes: unsigned tokens, brute-force, hardcoded salt, LAN HTTP (PE-008e export guard ✅ fixed) | 9 — needs core fixes | Open (a-d) | Needs Swift implementation |
| PE-009 | Apple HIG: 88 hardcoded fonts, 12 tap targets, 6 remaining swipe-to-delete without confirmation, a11y labels | 9 — needs Xcode prompts | Open (a-e) | Prompts not yet written |
| PE-010 | `createAuditSession()` silently dropped zone/sampleSize/notes | 13 — complete | ✅ Migration 061 adds columns; SQL insert updated | Option A chosen |
| PE-011 | 12 force unwraps in `ReportDateRange.swift` | 13 — complete | ✅ Fixed in commit 4b0c71a — guard/let + addingTimeInterval fallbacks | Closed |
| PE-012 | `Calendar.current.date(byAdding:)!` in 15 files | 13 — complete | ✅ Fixed in commit 4b0c71a — all 15 files updated to addingTimeInterval | Closed |
| PE-013 | Unplanned: `WarehouseLocationsPage` gained drag-and-drop floor plan + `StorageUnitDetailSheet` navigation path — not in warehouse plan | 11 — audit | 🔲 Document in ios-warehouse-pages.md | Low — quality improvement |

---

## PE-002 Resolution Notes

**All Phase 1 prompts archived to `done/` as of 2026-03-29.** GRDB fully removed from all iOS files. All 35A-35I, 66A-66C prompts complete or skipped as moot.

---

## Next Up (Priority Order)

> **Phase 1 COMPLETE.** All 279 Xcode AI prompts archived in `done/`. Working tree is clean, pushed to origin/main. Phase 2 begins — writing Xcode prompts for HIG polish + security.

1. **Write + run PE-009c prompt** (swipe-to-delete confirmations in 6 remaining files: IOSPreTripChecklistPage, IOSClockOutQuestionsPage, IOSReportTemplatesPage ×2, WarehouseWizardStep2, AddNotebookEntrySheet)
2. **Write + run PE-001 prompt** (Tool page rename: "Tool Registry"→"All Tools", "Tool Admin"→"Management")
3. **Write + run PE-009a prompt** (Dynamic Type: 88 hardcoded `.font(.system(size:))` → `.font(.title2)` / `.font(.body)` etc. across 51 files)
4. **Write + run PE-009b prompt** (12 undersized tap targets — add `.frame(minWidth: 44, minHeight: 44)`)
5. **Fix PE-008a-d** (core Swift: unsigned tokens, brute-force, legacy salt, LAN HTTP — direct Swift edits)
6. **Write PE-009d prompt** (color-only status indicators — add text/icon labels alongside)
7. **Write PE-009e prompt series** (accessibility labels — start with most-used pages)
8. **Write PE-003 prompt** (flex pool self-assign section on Scheduling page)

---

## Backlog

> Sorted by priority. Phase 1 Xcode prompts ALL complete. Backlog is now HIG + security only.

| Priority | Item | Source | Step | Blocked By |
|----------|------|--------|------|------------|
| 1 | Write PE-009c prompt — swipe-to-delete in 6 files | HIG / data safety | 10 | Write prompt first |
| 2 | Write PE-001 prompt — Tool naming rename | Plan alignment | 10 | Write prompt first |
| 3 | Write PE-009a prompt — Dynamic Type (88 fonts in 51 files) | Accessibility / App Store | 10 | Write prompt first |
| 4 | Write PE-009b prompt — tap targets (12 undersized) | Touch usability | 10 | Write prompt first |
| 5 | Fix PE-008a — unsigned session tokens | Security (high) | 9 | Core Swift edit |
| 6 | Fix PE-008b — no brute-force protection on PIN | Security (high) | 9 | Core Swift edit |
| 7 | Fix PE-008c — hardcoded legacy salt `:wiredpart` | Security (medium) | 9 | Core Swift edit |
| 8 | Fix PE-008d — LAN sync plain HTTP | Security (medium) | 9 | Larger change (TLS) |
| 9 | Write PE-009d prompt — color-only status indicators | Accessibility | 10 | Write prompt first |
| 10 | Write PE-009e prompt series — a11y labels (180+ views) | VoiceOver | 10 | Large effort |
| 11 | Write PE-003 prompt — flex pool self-assign on Scheduling | Plan alignment | 10 | Write prompt first |
| 12 | Write test coverage for PeopleService (47 methods, ~18 tested) | Quality | 7 | test-coverage-maintenance |
| 13 | Write test coverage for ChatService (33 methods, ~14 tested) | Quality | 7 | test-coverage-maintenance |
| 14 | Write test coverage for SettingsService (40 methods, ~17 tested) | Quality | 7 | test-coverage-maintenance |
| 15 | Document PE-013 warehouse drag-drop in ios-warehouse-pages.md | Plan alignment | 11 | Low priority |

---

## Recently Completed

| Date | What | Step Completed | Commits |
|------|------|----------------|---------|
| 2026-03-29 | **Phase 1 COMPLETE** — all 279 Xcode AI prompts archived in `done/` | Steps 10-13 | 740f480 |
| 2026-03-29 | PE-011 fixed: ReportDateRange.swift 12 force unwraps → guard/let + fallbacks | Steps 8-13 | 4b0c71a |
| 2026-03-29 | PE-012 fixed: Calendar force unwraps in 15 iOS files → addingTimeInterval() | Steps 8-13 | 4b0c71a |
| 2026-03-29 | PE-008e fixed: IOSDataExportPage export guard (export_reports permission) | Steps 9-13 | 4b0c71a |
| 2026-03-29 | PE-009c partial: swipe-to-delete confirmation in IOSReportsRouter | Steps 9-10 | 4b0c71a |
| 2026-03-29 | WarehouseLocationsPage: drag-and-drop floor plan + navigation path in detail | Steps 5-13 | 4b0c71a |
| 2026-03-29 | AuthService/SettingsService: `isTableNotFoundError` helper extracted | Steps 8-13 | 4b0c71a |
| 2026-03-29 | IOSClockPage: flex pool dispatch failure → visible errorMessage (silent→ UX) | Step 8 | 740f480 |
| 2026-03-29 | Fix PE-006 (67A): userId attribution in audit session + notebook auto-save | Steps 10-13 | Direct iOS fix |
| 2026-03-29 | 68 SQL bugs fixed total, 733 tests, all Phase 1 Xcode prompts done | Steps 5-7, 12-13 | Multiple |

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
| Apple HIG | 88 hardcoded font sizes bypass Dynamic Type (across 51 files — revised up from 55) | High — accessibility | Medium | 9 | 🔲 Xcode prompt needed |
| Apple HIG | 12 undersized tap targets (< 44x44pt) | High — touch usability | Quick | 9 | 🔲 Xcode prompt needed |
| Apple HIG | 5 swipe-to-delete without confirmation | Medium — data safety | Quick | 9 | 🔲 Xcode prompt needed |
| Apple HIG | Sparse accessibility labels (~8/180+ views) | High — VoiceOver | Large | 9 | 🔲 Xcode prompt series |
| Apple HIG | 9+ color-only status indicators | Medium — accessibility | Quick | 9 | 🔲 Xcode prompt needed |
| Security | Unsigned session tokens (forgeable) | High — auth bypass | Medium | 9 | 🔲 Core fix needed |
| Security | No brute-force protection on PIN login | High — account security | Quick | 9 | 🔲 Core fix needed |
| Security | Data export not gated behind admin permission | Medium — data exfiltration | Quick | 9 | 🔲 Xcode prompt needed |
| Security | Hardcoded legacy salt in PIN hashing | Medium — rainbow tables | Quick | 9 | 🔲 Core fix needed |
| Security | LAN sync uses plain HTTP | Medium — eavesdropping | Medium | 9 | 🔲 Core fix needed |
| Runtime Safety | 12 force unwraps in ReportDateRange.swift | Medium — crash all date-filtered pages | Quick | 13 | ✅ Fixed (4b0c71a) — guard/let + addingTimeInterval fallbacks |
| Runtime Safety | `Calendar.current.date(byAdding:)!` in 15 files | Low — practically safe | Quick | 13 | ✅ Fixed (4b0c71a) — all 15 files updated |
| IOSClockPage | Flex pool dispatch failure now shows errorMessage instead of silent print() | Low | — | 13 | ✅ Fixed (740f480) |
| Security | Data export not gated behind admin permission | Medium — data exfiltration | Quick | 13 | ✅ Fixed (4b0c71a) — export_reports permission check added |
| Unplanned | WarehouseLocationsPage drag-and-drop + StorageUnitDetailSheet nav path | Medium — UX improvement | Medium | 11 | ⬜ Document in ios-warehouse-pages.md (PE-013) |

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
| hunt-fix-verify | 2026-03-29 | 68 SQL bugs total, 188 tests added over 9 iterations | All found items fixed | ✅ Healthy — no new items since last run |
| test-coverage-maintenance | 2026-03-29 | Coverage gaps in PeopleService (38%), ChatService (42%), SettingsService (43%) | +185 tests total (733 passing) | ✅ Healthy — gaps remain, needs more runs |
| plan-enforcer | 2026-03-29 (run 2) | PE-010 drift item, iter 7 changes verified | Registry updated | ✅ Healthy — PE-013 unplanned warehouse changes need documenting |
| dev-improvement-scanner | 2026-03-29 (run 3) | PE-011, PE-012 found; PE-008e confirmed | All 3 now fixed in latest commits | ✅ Healthy |
| dev-pipeline-manager | 2026-03-29 (run 3) | Phase 1 complete, PE-011/012/008e all closed, PE-013 new | Pipeline updated | ✅ Healthy |
| github-issues-sync | — | — | — | ⚠️ Pending first run (auth required) |
| github-sync-and-review | 2026-03-29 22:07 | 2 new commits (740f480, 4b0c71a) | Pushed to origin/main ✅ | ✅ Healthy — branch up to date |
| weekly-cleanup | 2026-03-29 (Sun) | 4 .DS_Store files | Removed; dead code scan: clean | ✅ Healthy — next run 2026-04-05 |

---

## Pipeline Daily Summary Log

_Appended by dev-pipeline-manager each run._

---

### 2026-03-29 — Pipeline Manager Run 3 (Phase 1 Complete — Phase 2 Launch)

**Input:** 0 new GitHub issues, 0 new plans, 2 new commits since last run (740f480, 4b0c71a)

**Changes since last pipeline run:**

| Commit | What |
|--------|------|
| 740f480 | IOSClockPage: flex pool failure → visible errorMessage. Archived 9 prompts (35A, 35B, 35D, 35E, 35H, 66A, 66B, 66C) to done/ |
| 4b0c71a | PE-011 fixed (ReportDateRange 12 force unwraps). PE-012 fixed (Calendar! in 15 files). PE-008e fixed (export guard). IOSReportsRouter swipe-to-delete confirmation. WarehouseLocationsPage drag-and-drop + nav path. AuthService/SettingsService isTableNotFoundError helper extracted. BreakService divide-by-zero guard. |

**Phase status:**
- **Phase 1 Xcode AI Prompts: COMPLETE** — all 279 prompts archived in `xcode-ai/fix-prompts/done/`
- **Phase 2 begins** — HIG accessibility polish, security hardening, test coverage
- Phase 2 queue: 8 items in `xcode-ai/fix-prompts/00-fix-order.md` — all need prompt files written first

**PEs closed this run:** PE-011 ✅, PE-012 ✅, PE-008e ✅ (3 items)
**PEs opened:** PE-013 (unplanned WarehouseLocations features — document in plan)
**Plans created:** 0
**Q&A generated:** 0 (no new feature work needing owner input)
**New Xcode prompts written:** 0 (Phase 2 prompts not yet written)
**Tests:** 733/733 passing (no new tests this run)
**Build:** ✅ 0 errors, 0 warnings
**Commits pushed:** ✅ origin/main up to date
**Agent health:** 7/8 healthy, github-issues-sync still pending auth
**Active PEs:** 5 open (PE-001, PE-003, PE-007, PE-008a-d, PE-009a-e, PE-013)
**Backlog size:** 15 items (0 blocked on Q&A)
**Next priority:** Write PE-009c prompt (6 remaining swipe-to-delete without confirmation)

---

### 2026-03-29 — Dev Improvement Scanner Run 3 (Safety + Security + HIG Audit)

**Scope:** Full A-F scan per SKILL.md. Focused on runtime safety, security, Apple HIG, and UX polish.

**Part A — Runtime Safety:**
- ✅ Zero `as!` force casts in core
- ✅ Zero `try!` in core
- ✅ Zero empty `catch {}` blocks — all catch blocks rethrow or use `isTableNotFoundError` pattern
- ✅ `BinarySyncManager.deserialize` protected by `guard data.count >= 36`
- ✅ `WarehouseService partAssignments[0]` safe — inside `Dictionary(grouping:)` map which guarantees non-empty groups
- ✅ `LanSyncServer parts[0]/parts[1]` safe — protected by `guard parts.count >= 2`
- 🔲 **NEW PE-011**: 12 force unwraps in `ReportDateRange.swift` (shared utility). Most benign, but `cal.dateInterval(of: .weekOfYear, for:)!` is locale-dependent and could crash on unusual calendar locales. Breaks all date-filtered pages simultaneously.
- 🔲 **NEW PE-012**: `Calendar.current.date(byAdding: .day, value: -7, to: Date())!` default value pattern in 15 files. Low risk but should be `Date().addingTimeInterval(-7*86400)`.

**Part B — Security:**
- ✅ No hardcoded user IDs (`created_by = 1`) anywhere — PE-006 fix verified clean
- ✅ PIN hashing uses 10,000-iteration SHA-256 with per-user salt (migration in place for legacy devices)
- ✅ All SQL is parameterized — no string concatenation in queries
- 🔲 PE-008 confirmed: unsigned tokens (plain base64 JSON), no brute-force protection, hardcoded legacy salt `:wiredpart`, LAN HTTP — all still open
- 🔲 `IOSDataExportPage` confirmed: zero permission check. Any active user can export the full database. `export_reports` permission key exists in the permission map but is never checked at the iOS page level.
- Note: `AuthService.listRegisteredDevices/listActiveSessions` use inline `String(describing:).contains("no such table")` instead of the `isTableNotFoundError` helper — minor inconsistency, not tracked.

**Part C — Apple HIG:**
- ✅ Zero `NavigationView` — all pages use `NavigationStack`
- ✅ Zero `print()` in Features/ — only in App/ system managers (appropriate diagnostic logs)
- ✅ Zero TODO/FIXME in iOS codebase
- 🔲 **Updated PE-009**: hardcoded `.font(.system(size:))` count is **88 occurrences across 51 files** (was previously estimated at 55 — current grep confirms higher count)
- 🔲 `IOSJPOCreationPage.swift:209` dead button confirmed: `Button("Yes, for \(selectedJobName)") { }` — empty action

**Part D — UX Polish:**
- ✅ Pull-to-refresh: 133 `.refreshable` occurrences across 123 files — excellent coverage
- ✅ `EmptyStateView`: 47 occurrences across 37 files — good but not 100% coverage
- ✅ `ErrorStateView` and `errorMessage` patterns used consistently

**Part E — IOSClockPage Uncommitted Fix:**
- Uncommitted modification in git status: `IOSClockPage.swift` changed from `print("Flex pool dispatch creation failed: ...")` to setting `errorMessage = "Clocked in, but dispatch record could not be created."` — this is a quality improvement (silent failure → visible warning).
- Needs commit. Not a new PE — already good code waiting in working tree.

**Summary:**
- New PEs added: 2 (PE-011, PE-012)
- PE-009 count updated: 55 → 88 hardcoded fonts
- Confirmed all known PE-008 security items still open
- No new SQL integrity issues found (iter 7-9 fixes held)
- No force casts, no try!, no empty catches, no hardcoded user IDs found

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

---

### End-of-Day Sync — 2026-03-29

- Files committed: 5 (AppCore.swift, dev-pipeline.md, hunt-fix-tracker.md, ios-warehouse-pages.md, 00-fix-order.md)
- Commits created: 2 (`fix(onboarding)` + `docs(pipeline)`)
- Push status: ✅ success (4b0c71a → 66ff644 → origin/main)
- Tests: 733/733 passing (49 suites, 0 failures)
- Agent runs today: 6/7 healthy (github-issues-sync ⚠️ still pending auth)
  - hunt-fix-verify ✅ — 9 iterations, 68 SQL bugs fixed, Phase 1 complete
  - test-coverage-maintenance ✅ — 733 tests, coverage gaps remain in PeopleService/ChatService/SettingsService
  - plan-enforcer ✅ — PE-013 warehouse drag-drop documented, all Phase 1 changes aligned
  - dev-improvement-scanner ✅ — PE-011, PE-012, PE-008e found and fixed
  - dev-pipeline-manager ✅ — Phase 2 queue established (8 items)
  - github-sync-and-review ✅ — this run
  - github-issues-sync ⚠️ — pending auth, 0 issues processed
- Issues processed: 0 (auth not available in automated context)
- Bugs fixed: 1 (UserDefaults stale onboarding flags causing fresh-DB devices to skip onboarding)
- Pipeline health: ✅ Phase 1 COMPLETE — 279 prompts archived, Phase 2 HIG + security queue ready
