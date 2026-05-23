# UX audit: docs/designs vs app-page usability gaps (2026-05-23)

Issue: WEI-1942
Role: UXDesigner
Scope: docs-only / audit-only. No code changes.

## Sources read

- `docs/page-rebuild-tracker.md`
- `docs/plans/ios-page-review-tracker.md`
- `docs/plans/usability-hunter-plan.md`
- `docs/plans/ios-*-page*.md` design plans
- `docs/FEATURES.md`
- `xcode-ai/fix-prompts/00-fix-order.md`
- `xcode-ai/prompt-results-log.md`
- Current iOS Swift page inventory under `Weird Parts IOS/Weird Parts IOS/Features/`
- Open GitHub issue list sampled through `gh issue list --state open --limit 20 --json ...`
- Paperclip issue WEI-1942 details/activity/comments

## Executive reconciliation

The repository has two different “done” signals that should not be treated as the same thing:

1. Design/prompt completion: largely complete.
   - `docs/page-rebuild-tracker.md` says the older 44-page rebuild pass is PASS: 44/44 complete.
   - `xcode-ai/fix-prompts/00-fix-order.md` says Phase 1 all 279 prompts are archived in `done/`, and Phase 2 HIG/security work is complete.
   - `xcode-ai/prompt-results-log.md` says all 136 later prompts were verified/implemented and “Program ready for review.”

2. Human-visible usability confidence: still not complete.
   - `docs/plans/usability-hunter-plan.md` explicitly warns that compile/tests passing is not enough and calls out systemic usability risks: unsafe dismiss, silent failures, missing feedback, dead actions, form/input issues, and accessibility gaps.
   - The current Swift page inventory is much larger than the historical 44-page rebuild matrix: about 130 `*Page.swift` user-facing pages in feature folders.
   - A lightweight static UX heuristic scan still finds many pages with risk markers such as `.sheet` without an obvious `interactiveDismissDisabled`, `try?`, placeholders/“Coming Soon”, TODO/FIXME, text fields without local keyboard-dismiss affordance, and list-like pages without an obvious empty state. These are not all confirmed bugs, but they are exactly the pages that need human-visible QA before beta.

Bottom line: the design implementation pass is mostly done, but the next beta-readiness work should be verification and cleanup, not another broad redesign.

## Tracker/doc gaps to fix first

These are coordination gaps that will confuse engineering agents unless reconciled:

1. `docs/plans/ios-page-review-tracker.md` is stale relative to `xcode-ai/prompt-results-log.md`.
   - It still reports “188 prompts written · 133 DONE · 55 queued · 5 areas designed (prompts pending).”
   - The prompt results log later records 31A-67A-style work as completed/already implemented.
   - Engineering task: update the tracker to separate “design prompts originally queued” from “prompt-results-log later verified/implemented.”

2. `docs/page-rebuild-tracker.md` says 44/44 pages complete, but the live app has far more user-facing pages.
   - Engineering/QA task: rename or annotate the 44-page tracker as the historical rebuild pass, not the full current app-page inventory.

3. `xcode-ai/fix-prompts/00-fix-order.md` still shows a small active prompt queue at the top despite broad completion language.
   - Active-looking items: PE-051 dismiss guard tools sheets; PE-046 through PE-049 PE-COLORS Phase 2 follow-ups.
   - Engineering task: either implement/archive these or mark them superseded with evidence.

## What is already marked done / design-complete

### Cross-cutting and foundation

- Foundation fixes 01-05: done.
- Missing CRUD 06-08: done.
- Security/service-layer cleanup 09-10: done.
- HIG/accessibility pass: done per prompt order and results log, including Dynamic Type, tap targets, swipe delete replacements, color-only status, and accessibility labels.
- Page help infrastructure exists, but coverage remains a confidence item because GitHub issues show missing registry mappings.

### Dashboard / Parts / Orders / Warehouse prompt families

- Dashboard 12A-12F: done.
- Parts catalog/categories/brands/suppliers/pricing/companions/forecasting/import-export prompt families: largely done.
- Orders PO/JPO/procurement/receiving/returns prompt families 26A-30E: recorded done in design tracker / results log.
- Warehouse prompts 31A-31I were originally shown queued in the tracker, but later prompt-results-log sections show floor plan, audit confidence, onboarding wizard, and warehouse UX prompts as completed/already implemented.

### People / Jobs / Scheduling / Chat / Notebooks / Tools / Fleet / Reports / Office / Settings

- `prompt-results-log.md` records implementation or “already implemented” status for:
  - Teams detail and People prompts 44A-44F.
  - Jobs prompts 45A-45D.
  - Scheduling prompts 46A-46F.
  - Chat prompts 42A-42D.
  - Notebooks prompts 43A-43E.
  - Tools detail/trades/checkout/maintenance areas.
  - Fleet, Reports, Office, Settings pages via later prompt groups.

## Human-visible behavior verification still needed

These are not all new bugs. They are the concrete page groups that should be opened in the running app/simulator and verified by behavior, because static docs and prompt logs cannot prove the real UX.

### P0 / beta-blocking verification

1. Clock in/out and daily work loop
   - Pages: `IOSClockPage`, `DashboardDailyReportPage`, `IOSDailyReportsPage`, clock-out questions/settings.
   - Why: GitHub #599 “Clock in and out” is open; #600 “Daily Report” is open; the clock page is large and central.
   - Verify: clock in, switch to a todo, start/end break, clock out, daily report generation, stale AI context, unsaved form behavior, no silent errors.
   - Recommended engineering tasks: close/triage #599 and #600 with direct reproduction evidence.

2. Receiving / JPO / PO / procurement flow
   - Pages: `IOSReceiveShipmentPage`, `IOSJPOCreationPage`, `IOSJPODetailPage`, `IOSJPOsPage`, `IOSPODetailPage`, `IOSProcurementPage`, `IOSOrderStagingPage`, `IOSPartsOrderManagementPage`, `IOSReturnsPage`.
   - Why: many pages are very large and workflow-critical; open GitHub #572 says receiving routing silently ignores damaged/used Unknown Part items.
   - Verify: create JPO, approve/hold/reject line, generate PO, receive shipment, damaged/unknown routing, partial/backorder, return, save-and-exit/draft restore, all error states visible.
   - Recommended engineering task: make #572 a P1 workflow bug if not already assigned.

3. Warehouse movement / floor plan / audit loop
   - Pages: `WarehouseDashboardPage`, `WarehouseMovementsPage`, `WarehouseLocationsPage`, `IOSAuditPage`, `IOSOrganizationAuditPage`, `IOSInventoryGridPage`, `IOSReceivingPage`, `IOSStagingPage`.
   - Why: open GitHub #567, #555, #501 point at real warehouse QA holes; some pages still have placeholder markers from static scan.
   - Verify: zone placement save/resume, audit session update paths, seeded verification part visibility, floor plan interactions, movement confirmation/cancel, receiving area routing.
   - Recommended engineering tasks: group #567/#555/#501 under a Warehouse QA verification push.

4. Settings build/runtime confidence
   - Pages: many Settings pages plus `SettingsPrivacyPage` if present in project.
   - Why: open GitHub #561 reports a build issue; #571 reports missing AI help registry entry.
   - Verify: settings navigation compiles, every settings page opens, save/reset actions show success/failure, AI help maps correctly.
   - Recommended engineering task: fix #561 before any further UX pass depends on simulator navigation.

### P1 / should complete before beta

5. Dismiss safety campaign remains confusing.
   - Evidence: `00-fix-order.md` still shows PE-051 “Dismiss Guard: Phase 1D Tools sheets” as active; static scan found many pages with `.sheet` and no local `interactiveDismissDisabled` string.
   - Caveat: some pages may use shared wrappers, so the scan is a triage list, not a bug list.
   - Verify: form sheets in Tools, Fleet, Reports, Warehouse, Orders, Settings preserve unsaved work or intentionally allow discard.
   - Recommended engineering task: run the canonical PE-044 dismiss-safety checklist against every page that still has `.sheet`.

6. AI help / page context freshness.
   - Evidence: open #582 Fleet AI help registry missing; #571 Settings AI help registry missing; #569 Jobs/Warehouse/AI stale page contexts after filters; #554 clock-out questionnaire context stale after edits.
   - Verify: AI helper opens on Fleet, Settings, Jobs/Warehouse pages; context updates after search/filter/tab/form changes.
   - Recommended engineering task: one cross-cutting “AI page context and HelpContentRegistry coverage” task.

7. Scheduling usability.
   - Evidence: open #616 “on the scheduling page there are a few things”; #612 subcontractor scheduled dates; #610 next 14 days preview.
   - Pages: `IOSScheduleCalendarPage`, `IOSDispatchPage`, `IOSShortTermPipelinePage`, `IOSLongTermPipelinePage`, `IOSFlexPoolPage`, `IOSScheduleConfigPage`, `IOSTimeOffPage`.
   - Verify: 14-day preview, subcontractor dates, dispatch drag/drop or fallback, time-off conflicts, flex pool claim, config saves.
   - Recommended engineering task: triage #616/#612/#610 into one Scheduling UX milestone with acceptance steps.

8. Parts import and PE-COLORS completion.
   - Evidence: open #597 “Parts importing”; active-looking PE-046 through PE-049 in fix-order; categories plan still notes part numbers/search items were not yet built in an older section, while later logs say PE-COLORS phases landed.
   - Pages: `PartsImportExportPage`, `PartsCategoriesPage`, `PartsCatalogPage`, `PartsSuppliersPage`, `PartsPricingPage`.
   - Verify: import preview/errors/rollback, category tree SKU rows, named-only variants, supplier linked-brand picker, catalog search by color-level part number.
   - Recommended engineering task: reconcile PE-COLORS docs and verify #597 with a sample import.

9. Chat / RFI / Q&A operational confidence.
   - Evidence: open #553 unread badge count security/visibility bug; chat pages still contain TODO/FIXME markers in static scan.
   - Pages: `IOSChannelsPage`, `IOSQuestionsPage`, `IOSRFIListPage`, message thread pages.
   - Verify: channel membership scoping, unread badges, escalation ladder, attachments/reference picker, RFI status transitions, no unauthorized channel counts.
   - Recommended engineering task: treat #553 as security-adjacent P1 and add a chat walkthrough test.

10. Notebooks and daily-report integration.
   - Evidence: design is ambitious; current code is large; open #600 daily report overlaps. Static scan found placeholder/try? markers in notebook detail.
   - Pages: `IOSNotebooksListPage`, `IOSNotebookDetailPage`, `IOSJobNotebooksPage`, `IOSNotebookTemplatesPage`.
   - Verify: block editing, todo classification, panel schedule builder, template apply, conflict resolution, daily report pull-through.
   - Recommended engineering task: user-visible notebook smoke test with seeded notebook/job/todo data.

### P2 / polish and completeness

11. Reports and Office dashboards.
   - Pages: Reports category pages, Office dashboard, approvals, spending, warehouse exec.
   - Verify: empty states, period locking, exports, no report filters drop historical inactive records, office approvals match permissions.
   - Recommended task: report/office manual QA checklist; not a redesign.

12. Fleet and Tools.
   - Evidence: #582 Fleet AI help; PE-051 Tools dismiss guard; many fleet pages are modest/simple and should be quick to verify.
   - Verify: vehicle/trailer detail, inspection, maintenance, mileage/fuel, tool checkout/return/trade/lost-stolen, pending edit approval.
   - Recommended task: one Fleet+Tools smoke test pass, with dismiss safety included.

13. Placeholder/dead-text cleanup.
   - Static scan found placeholder-like markers in `IOSDashboardQRScannerPage`, `IOSNotebookDetailPage`, `IOSSpendingDashboardPage`, `PartsCompanionsPage`, `IOSContactDetailPage`, `IOSTeamsPage`, `IOSAuditPage`, `IOSWarehouseNetworkPage`, and `NotificationPrefsPage`.
   - Some may be valid instructional text rather than dead UI.
   - Recommended task: inspect each marker and either replace with real behavior or document why it is intentional.

## Concrete engineering task candidates

If creating follow-up Paperclip/GitHub tasks, use these titles and acceptance criteria:

1. `[Docs][UX] Reconcile iOS page tracker with prompt-results-log completion evidence`
   - Acceptance: tracker no longer says 55 queued / 5 prompt-pending areas unless each is still truly pending; historical 44-page tracker is labeled historical.

2. `[UX][P1] Finish dismiss-safety verification for remaining sheet-based pages`
   - Acceptance: every form/action sheet either uses shared guarded wrapper or has local dirty/saving dismiss protection; false positives documented.

3. `[AI][P1] Complete HelpContentRegistry and page-context freshness coverage`
   - Acceptance: closes/links #571, #582, #569, #554; context updates after filters/search/tabs/forms.

4. `[Warehouse][P1] Verify and close warehouse floor-plan/audit/receiving QA bugs`
   - Acceptance: #567, #555, #501, #572 are each reproduced/fixed/closed or explicitly split.

5. `[Clock][P1] Clock in/out + daily report human-visible walkthrough`
   - Acceptance: #599 and #600 have reproduction evidence and fixes or are closed with verified behavior.

6. `[Scheduling][P1] Scheduling UX triage: 14-day preview, subcontractor dates, dispatch issues`
   - Acceptance: #616, #612, #610 converted into tested flows with screenshots or test notes.

7. `[Parts][P1] Parts import and PE-COLORS verification pass`
   - Acceptance: #597 verified with sample import; PE-046 through PE-049 either archived as done or implemented.

8. `[Chat][P1] Membership-safe unread badges and RFI/Q&A walkthrough`
   - Acceptance: #553 fixed/verified; chat/RFI pages pass a seeded user walkthrough.

9. `[Settings][P0/P1] Restore settings build/navigation confidence`
   - Acceptance: #561 fixed if still present; all Settings pages open and save/revert actions visibly succeed/fail.

10. `[QA][P2] Page placeholder/dead-action cleanup sweep`
    - Acceptance: placeholder/TODO markers in the listed pages are replaced, confirmed intentional, or converted to issues.

## Recommended next step

Do not start another broad redesign. Start with a narrow verification milestone:

1. Fix/confirm build health and #561.
2. Run human-visible walkthroughs for Clock, Receiving/JPO/PO, Warehouse audit/floor-plan, Settings, and Scheduling.
3. File or close focused engineering issues from observed behavior.
4. Only after those P0/P1 flows are green, run the remaining P2 Fleet/Tools/Reports/Office/placeholder polish pass.

This turns the existing design work into beta confidence without churning completed prompt history.
