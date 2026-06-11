# iOS Page-by-Page Review Tracker

> **Purpose:** Master tracking document for the iOS app design review, redesign, and page-level implementation process. Records what's been reviewed, design decisions made, prompts written, and what still needs work.
>
> **Workflow:** Claude reviews each page → identifies issues → records design decisions → writes Xcode AI prompts → user implements via Xcode AI → user reports results → Claude audits.
>
> **Prompt files:** `xcode-ai/fix-prompts/` (active) · `xcode-ai/fix-prompts/done/` (archived)
> **Prompt tracking:** `xcode-ai/fix-prompts/00-fix-order.md` (194 prompt entries)
> **Results log:** `xcode-ai/prompt-results-log.md`

---

## 2026-05-23 Reconciliation Note for GH#649 / WEI-2005

This tracker began as a design-review and Xcode-AI prompt planning ledger. It should no longer be read as the live beta QA status. There are four separate signals:

1. Historical 44-page rebuild pass: `docs/page-rebuild-tracker.md` records a historical 44/44 April 2026 rebuild matrix, now explicitly labeled historical.
2. Original design prompt queue: the table below preserves what prompt chains were written or planned during the March design-review period.
3. Later implementation evidence: `xcode-ai/prompt-results-log.md` records many later prompts/results as SUCCESS, implemented, or already implemented; `xcode-ai/fix-prompts/00-fix-order.md` says Phase 1 all 279 prompts were archived and Phase 2 HIG/security work is complete.
4. Current human-visible QA: `docs/plans/ux-audit-page-gap-list-2026-05-23.md` and `docs/testing/wei-1944-full-app-usability-verification-matrix.md` define the remaining simulator/manual verification work before beta confidence.

Therefore, statuses such as “queued” below mean “originally queued in the design/prompt ledger” only when backed by the current fix-order queue. They are not automatic proof of unfinished implementation, and “DONE” is not automatic proof of current human-visible usability.

### Current prompt-ledger interpretation

- Completed/archive evidence: `xcode-ai/fix-prompts/00-fix-order.md` states Phase 1 prompts 01–67A are archived in `done/`, and Phase 2 HIG/security work is complete.
- Later result evidence: `xcode-ai/prompt-results-log.md` includes implementation/result entries for Jobs 45A+, Scheduling 46A+, Tools 47B/47D/47E, Fleet 48A–48E, Reports 49A–49D, Office 50A–50D, Settings/standards/sync 51A–55A, and related later groups.
- Still active-looking prompt work in the current queue: PE-046 through PE-049 (PE-COLORS Phase 2 UI prompts to be written) and PE-051 (Tools sheet dismiss guard after PE-COLORS).
- Current QA links: use the WEI-1944 matrix for “what still needs human-visible verification,” not the old prompt counts.

---

## Review Progress Overview

| Area | Pages | Reviewed | Prompts | Status |
|------|-------|----------|---------|--------|
| Foundation (cross-cutting) | — | ✅ | 01-05 (5) | All DONE |
| Missing CRUD (cross-cutting) | — | ✅ | 06-08 (3) | All DONE |
| Security (cross-cutting) | — | ✅ | 09 (1) | DONE |
| Service Layer Bugs (cross-cutting) | — | ✅ | 10 (1) | DONE |
| Dashboard | 4 pages | ✅ | 12A-12F (6) | All DONE |
| Parts → Catalog | 1 page | ✅ | 13A-13E (5) | All DONE |
| Parts → Categories | 6 files | ✅ | 14A-14G (7) | All DONE |
| Parts → Brands | 1 page | ✅ | 11A-11C, 15A-15C (6) | All DONE |
| Parts → Suppliers | 1 page | ✅ | 15A-15C, 17A-17H (11) | All DONE |
| Parts → Pricing | 1 page | ✅ | 16A-16I (9) | All DONE |
| Parts → Companions | 1 page | ✅ | 19A-19K (11) | All DONE |
| Parts → Forecasting | 1 page | ✅ | 23A-23H (8) | All DONE |
| Parts → Import/Export | 1 page | ✅ | 24A (1) | DONE |
| QR System (cross-cutting) | multiple | ✅ | 20A-20D, 21A-21B (6) | All DONE |
| Supplier Bridge (cross-cutting) | multiple | ✅ | 22A-22C (3) | All DONE |
| Review Cleanup (cross-cutting) | multiple | ✅ | 18A (1) | DONE |
| Orders | 14 files | ✅ | 26A-30E (22) | All DONE |
| Warehouse | 15 files | ✅ | 31A-31I (9) | All DONE |
| Cross-cutting Cleanup | multiple | ✅ | 32A-32J (10) | All DONE |
| Cross-cutting Polish | multiple | ✅ | 33A-33H (8) | All DONE |
| UI Quality Audit | multiple | ✅ | 34A (1) | Historical prompt; see results/fix-order + current WEI-1944 QA matrix |
| Targeted Fixes | multiple | ✅ | 35A-35I (9) | Historical prompt group; later fixes/results exist, use current issue queue for residuals |
| Floor Plan System | warehouse | ✅ | 36A-36D (4) | Later implementation evidence exists; current simulator/manual QA still required |
| Audit Confidence System | warehouse | ✅ | 37A-37D (4) | Later implementation evidence exists; current simulator/manual QA still required |
| Break/Lunch Compliance | clock | ✅ | 38A-38B (2) | Later implementation evidence exists; verify in Clock QA matrix |
| Hats Permission Audit | cross-cutting | ✅ | 39A (1) | Later cleanup/security evidence exists; verify permission behavior in QA matrix |
| Clock To-Do Integration | clock | ✅ | 40A-40B (2) | Historical prompt ledger; current Clock walkthrough remains high-priority QA |
| Teams Detail | people | ✅ | 41A (1) | Later People/Teams evidence exists; verify People flows in QA matrix |
| Chat | 9 files | ✅ Design | 42A-42D (4) | Later result evidence exists; chat/RFI/Q&A still needs human-visible verification |
| Notebooks | 7 files | ✅ Design | 43A-43E (5) | Later result evidence exists; notebook editor/manual QA remains required |
| People | 11 files | ✅ Design | 44A-44F (6) | Later People result evidence exists; permission/privacy QA remains required |
| Jobs | 11 files | ✅ Design | 45A-45D (4) | Later Jobs result evidence exists; current Jobs/Clock QA remains high priority |
| Scheduling | 12 files | ✅ Design | 46A-46F (6) | Later Scheduling result evidence exists; current Scheduling QA remains high priority |
| Tools | 7 files | ✅ Design | 47-series + PE-051 | Later Tools result evidence exists; PE-051 dismiss guard remains active-looking |
| Fleet | 17 files | ✅ Design | 48A-48E | Later Fleet result evidence exists; verify Fleet native flows in QA matrix |
| Reports | 9 files | ✅ Design | 49A-49D | Later Reports result evidence exists; export/manual QA remains required |
| Office | 6 files | ✅ Design | 50A-50D | Later Office result evidence exists; approval/financial QA remains required |
| Settings | 23 files | ✅ Design | 52A+ / settings groups | Later Settings result evidence exists; deep settings/manual QA remains required |

**Historical design-ledger totals:** 188 prompts written in this tracker; older “133 DONE / 55 queued / 5 prompt-pending areas” counts are superseded by `xcode-ai/prompt-results-log.md` and `xcode-ai/fix-prompts/00-fix-order.md`. Current active-looking prompt work is PE-046–PE-049 and PE-051; current human-visible QA status is in the WEI-1944 matrix.

---

## Completed Reviews — What Was Done & Decisions Made

### Foundation Fixes (Prompts 01-05) — DONE

Cross-cutting audit of the entire app for structural issues.

| Prompt | What it fixed | Files touched |
|--------|--------------|---------------|
| 01 | Multiple `.sheet()` conflicts → single `.sheet(item:)` enum pattern | 7 files |
| 02 | Blank screens instead of errors → `@State loadError` + `ContentUnavailableView` everywhere | 19 files |
| 03 | Infinite loading spinners → timeout + retry | Multiple |
| 04 | Fake sync fools users → honest "not available yet" messages | 3 files |
| 05 | App crashes on DB failure → safe optionals, `AppCoreError` enum | AppCore |

**Key decisions:**
- **Single `.sheet(item:)` rule:** SwiftUI only respects the first `.sheet()` modifier. Use `ActiveSheet` enum.
- **Error visibility:** Every `loadData()` must have `@State private var loadError: String?` with UI display.
- **44px touch targets:** All tappable elements use `.frame(minHeight: 44)`.
- **Smart Cards are a PROGRAM STANDARD:** Stat card filters (tap to filter, tap again for all, counts on each card) replace horizontal chip bars on ALL list pages. This is the standard filter pattern across the entire app.
- **Help/Info button on ALL pages:** Every page gets a help button explaining what it does and how to use it.
- **Full audit trail on ALL parts:** `part_change_log` table tracks who changed what, when, across the entire app. Visible in part detail view.
- **AI Assistant capabilities (PROGRAM STANDARD):**
  - Has access to page-specific detailed info for the OPEN page
  - Has general read-only info for everything else in the program
  - Can activate/change card filters to surface relevant info on the current page
  - Can give instructions on what to click (but CANNOT navigate for the user)
  - Knows the full program layout and can guide users to the right page
  - LOCKED to user-specific info (respects hat permissions)
  - CANNOT edit, modify, or delete any data — strictly read + filter activation
  - Needs significant work — this is an ongoing feature, not a one-prompt fix

### CRUD & Security (Prompts 06-10) — DONE

| Prompt | What it fixed |
|--------|--------------|
| 06 | Missing add/edit/delete for employees, customers, job tabs |
| 07 | Missing PO line items, receive workflow, audit start |
| 08 | Missing time-off approval, chat channel creation |
| 09 | Weak PIN hashing → per-user salt + 10K iterations |
| 10 | Wrong table names, missing columns, broken counts in services |

### Dashboard (Prompts 12A-12F) — DONE

Full redesign of the Dashboard tab with 4 sub-tabs.

| Prompt | Feature |
|--------|---------|
| 12A | Navigation restructure: Overview, Clock, Daily Report, QR Scanner tabs. Clock removed from Jobs. |
| 12B | Clock-in status banner on Dashboard Overview |
| 12C | Inline clock-in with GPS-sorted job picker, shop/optional job link |
| 12D | GPS geofencing: auto-detect job transitions, lock until questionnaire answered |
| 12E | Enhanced Daily Report: my hours, team status, fast actions |
| 12F | Continuous QR scanner with lock/auto-lock |

**Key decisions:**
- Clock is a Dashboard feature, not a Jobs feature (users clock in/out all day regardless of which job they're browsing)
- GPS geofencing triggers questionnaire — can't ignore a location change
- QR scanner runs continuously with auto-lock after scan (prevents accidental double-scans)

### Parts → Catalog (Prompts 13A-13E) — DONE

| Prompt | Feature |
|--------|---------|
| 13A | Fixed search bar at top, always visible (was collapsible) |
| 13B | Always-visible filter chips row (was hidden behind toggle) |
| 13C | Part detail sheet with delete confirmation |
| 13D | Natural language search → auto-detects filters ("red copper fittings") |
| 13E | AI assistant reads/controls catalog filters via NotificationCenter |

**Key decisions:**
- Search always visible — users search constantly in the field
- NL search parses color, category, brand, type from natural language
- AI integration uses `NotificationCenter` for page context (`.catalogPageActive` / `.catalogPageInactive`)

### Parts → Categories (Prompts 14A-14G) — DONE

| Prompt | Feature |
|--------|---------|
| 14A | Brand > Color nesting (was flat list) |
| 14B | Alphabetical sort, count badges, bigger add buttons |
| 14C | Tree search / filter |
| 14D | Save error feedback in all 4 form sheets |
| 14E | Smart Delete: inventory check before delete, empty shelf mode with scheduled_deletions table |
| 14F | Office page for approving scheduled deletions (Admin/Manager) |
| 14G | Help button + hierarchy explainer for new users |

**Key decisions:**
- **Smart Delete:** Can't delete a category/brand/etc with active inventory. Instead: "Empty Shelf Mode" — schedule for deletion after stock depletes, with office approval workflow
- **Hierarchy:** Category → Style → Type → Brand → Color (5 levels). Brands nest under types, colors nest under brands.

### Parts → Brands & Suppliers (Prompts 11A-11C, 15A-15C) — DONE

| Prompt | Feature |
|--------|---------|
| 11A | Service methods for brand-supplier link/unlink |
| 11B | Brand detail view with linked suppliers list |
| 11C | Checkbox picker for managing brand-supplier links |
| 15A | Removed raw SQL from both pages → PartsService methods |
| 15B | Delete confirmations, save error feedback on both pages |
| 15C | Fixed nested .sheet conflict in SupplierDetailSheet |

### Parts → Pricing (Prompts 16A-16I) — ALL DONE

| Prompt | Feature | Status |
|--------|---------|--------|
| 16A | Migration: pricing_tiers, price_history, cost_layer_consumptions tables | ✅ DONE |
| 16B | FIFO/LIFO cost engine: 9 service methods | ✅ DONE |
| 16C | Hierarchical pricing: Category→Style→Type→Brand→Part resolution | ✅ DONE |
| 16D | Pricing page UI rebuild: raw SQL removed, full rewrite (389→733 lines) | ✅ DONE |
| 16E | Price override flow: set tier pricing, confirm conflicts | ✅ DONE |
| 16F | Bulk markup + settings: bulk edit, markup/margin toggle, stale threshold | ✅ DONE |
| 16G | Stale alerts + receiving: price age warnings, verification during receive | ✅ DONE |
| 16H | Catalog pricing + view modes: pricing columns on catalog, layout options | ✅ DONE |
| 16I | Pricing AI integration: read-only AI for pricing questions | ✅ DONE |

**Key decisions:**
- **FIFO for consumption:** Oldest cost batches consumed first when parts go to jobs
- **LIFO for returns only:** Most recent consumed batches restored first
- **Hierarchical pricing:** Category → Style → Type → Brand → Part. Most specific wins. Higher-level changes DON'T auto-replace lower overrides.
- **Override confirmation:** Strictly one-at-a-time. Each override shows old vs new, user picks Replace or Keep.
- **Markup vs Margin:** Company-wide setting (toggle in Settings). Markup default. Minimum margin = 0%.
- **Stale alerts:** Parts not price-updated in X days (default 90) flagged during ordering.

### Parts → Companions (Prompts 19A-19K) — ALL DONE

Companion rules: "when you buy X, you probably also need Y."

| Prompt | Feature |
|--------|---------|
| 19A | Migration: polls, votes, auto-discovery tables, type_id on sources/targets |
| 19B | Rules + points service: hierarchy CRUD, soft delete, co-occurrence engine |
| 19C | Polls + voting service: weekly polls, vote casting, admin controls |
| 19D | Page cleanup: raw SQL → service, error banners, orphan indicators |
| 19E | Rule form rebuild: cascading category/style/type pickers |
| 19F | Polls UI: 3rd tab, vote cards, admin lock/skip/preview |
| 19G | Clock-out integration: companion polls as optional Yes/No questions |
| 19H | Testing sandbox: "What If" scenario builder with real job data |
| 19I | Admin dashboard: voting accuracy, poll history, rule counts |
| 19J | Auto-discovery engine: style/type drill-down, app-launch trigger |
| 19K | AI integration: 4 read-only tools |

**Key decisions:**
- **Points-based auto-discovery:** Scans `job_parts` co-occurrences. 1 point per min(qty_A, qty_B) pair. Thresholds: 100 pts, 15+ co-occurrences, 15% confidence, 3-48 month window.
- **Weekly polls:** One new poll/week from highest-point pair. 30-day or all-voted expiry. `companion_vote_power` permission (Admin, Manager, Lead) controls weight.
- **Admin controls:** Lock result (vote_veto permission), Skip (-50 points), Preview next week.
- **Hierarchical cascade:** Category → Style → Type → Brand. Each level gets its own poll. Parent delete → children flagged red for 30 days, then auto-purge.
- **Training questions:** When no qualifying poll exists, show practice question from closest-to-threshold pairs.
- **Clock-out:** Polls 7+ days old appear as optional Yes/No during clock-out questionnaire.
- **Tied polls:** Don't re-ask for 2 months (`tied_cooldown_until`).
- **Rejection:** -100 points AND -100 likelihood per rejection. 5 rejections = permanently blocked (admin can reset).

### Parts → Forecasting (Prompts 23A-23H) — ALL DONE

| Prompt | Feature | Status |
|--------|---------|--------|
| 23A | Cleanup: raw SQL → service, platform guards, recalculate button, trend indicators | ✅ DONE |
| 23B | AI integration: GetForecastDataTool, page context notifications, read-only | ✅ DONE |
| 23C | Stat cards as toggle filters (replace chip bar) | ✅ DONE |
| 23D | Per-location backbone: migration, per-location forecast service methods | ✅ DONE |
| 23E | Forecast settings: per-location-type defaults + per-truck overrides, ADU vs APW, free space | ✅ DONE |
| 23F | Target recommendation engine: daily pick, all 3 values, cooldown, category changes | ✅ DONE |
| 23G | Location picker UI, recommendation cards with approve/dismiss | ✅ DONE |
| 23H | Detail panel redesign: full part editor, stock health bars per location | ✅ DONE |

**Key decisions:**
- **Trend indicators:** ADU-30 vs ADU-90 comparison. >15% = trending up (red arrow), <85% = trending down (green arrow), else stable.
- **Stat cards as filters:** Cards ARE the filters. Tap to filter, tap again to deselect. Chip bar deleted.
- **Per-location forecasting:** `location_stock_targets` table with per-location MIN/TARGET/MAX + forecast data.
- **Background recalc:** Daily auto-run + Dashboard task card. Manual button stays for on-demand.
- **Forecast auto-approve:** Per-part auto-add toggle + below MIN at location + ≥80% certainty. Below 80% → physical audit first. Auto-approve is per-location.
- **Truck/trailer below MIN:** Check if shop has stock first → stage movement. If shop doesn't have it → wishlist item.
- **Wishlist:** Separate from Procurement, feeds into it. 3 sections (User/Forecast/Auto). Per-location auto-approve.
- **Procurement redesign:** Demand consolidation (JPO + Wishlist + Forecast + Auto). Groups by part. All suppliers shown. Generic=supplier locked per job, Branded=any supplier.
- **Shop ADU (parts/day)** vs **Truck APW (parts/X-weeks)**. Per-truck configurable window (1-6 weeks).
- **Common vs Critical** per part per location. Auto-suggest category changes at 6 months.
- **Full plan:** See `docs/plans/inventory-intelligence-system.md`

### QR System (Prompts 20A-20D, 21A-21B) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 20A | Reusable `QRScanSheet` component + Warehouse integration (PO scan, part/bin scan) |
| 20B | Orders integration (line item scan, supplier scan, PO lookup, JPO scan) |
| 20C | Jobs (clock-in scan) + Tools (checkout/return/registry scan) |
| 20D | Catalog (part/barcode/UPC/EAN scan) + People (badge scan) |
| 21A | QR Label PDF Engine: 6 sizes, 11 paper types, 6 layouts, sticker sheet support |
| 21B | QR Label Print UI: size/layout/paper pickers, used sticker picker, iOS native print |

**Key decisions:**
- **QRScanSheet:** Reusable component wrapping `IOSQRScanner` + `QRAutoFillService`. `expectedType: QREntityType?` filter — nil accepts any type.
- **Label sizes:** Square (2×2"), Tall (1.5×3"), Wide (3×1.5"), Long (4×1"), Small (1×1"), Standard (2×1")
- **Paper sizes:** Letter, Legal, A4, Avery 5160/5163/5164/5165/5167/8160, Thermal 2×1/4×6
- **Partial sheet printing:** `usedPositions: Set<Int>` — user taps visual grid to mark used sticker positions
- **Barcode support:** Catalog scan accepts manufacturer UPC/EAN in addition to WiredPart QR codes

### Supplier Communication Bridge (Prompts 22A-22C) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 22A | Migration: `supplier_channel_bridges` + `supplier_messages` tables. Service methods for bridge channels. |
| 22B | UI: orange "Supplier" badges, detail page messaging, direction indicators, PO reference attachments |
| 22C | Job-linked supplier channels, supplier RFI integration, unread badges on job detail |

**Key decisions:**
- **Bridge approach:** No supplier user accounts. Internal users act as intermediaries. `direction` field (inbound/outbound) tracks message flow.
- **`invite_token`:** Reserved for future direct supplier access without full accounts.
- **Job context:** Supplier channels can be linked to specific jobs for job-scoped communication.

### Review Cleanup (Prompt 18A) — DONE

| Prompt | Feature |
|--------|---------|
| 18A | Error visibility in 3 category components, dead imports, minor bugs across reviewed pages |

---

## Designed Pages — Design Complete, Prompts Pending

These areas have comprehensive design plans saved in `docs/plans/`. Next step: read current code, write Xcode AI prompts.

### Jobs (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-jobs-pages.md`
**Files:** `JobsListPage`, `IOSJobDetailPage`, `IOSJobDetailTabView`, `IOSCreateJobSheet`, `IOSEditJobSheet`, `IOSClockPage`, `IOSDailyReportsPage`, `IOSQuestionnairePage`, `JobReportsPage`, `LaborPage`

**Key design decisions:**
- 7 job statuses: Active, On Hold, Payment Hold (workers see "On Hold", managers see "$"), Completed, Cancelled, Warranty, Continuous
- Smart cards on list page with AI summary per card (cached 1hr), stage progression bar, dual progress bars (hours + budget, only if data exists)
- Per-job dashboard with stage progression, smart cards, AI summary, today's activity, quick actions (hat-gated), warranty info, financial summary
- Continuous jobs: to-do driven, per-to-do warranty, only qualified workers, light gray appearance
- Payment hold: red banner, workers can't clock in, resume hat-locked
- Clock integration: to-do picker on clock-in, mark done + pick next, switch to-do, work type (New/Warranty), live timer, one-action job switch
- Warranty: default 1 year adjustable, continuous jobs get per-to-do warranty, warranty work classification with manager review
- Swipe actions: AI summary (right), status change (left, managers only)

### Chat (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-chat-pages.md`
**Files:** `IOSChannelsPage`, `IOSMessageThreadView`, `CreateChannelSheet`, `IOSQuestionsPage`, `IOSQAQuestionForm`, `IOSRFIListPage`

**Key design decisions:**
- Unified inbox: all messages/Q&A/RFI/supplier/DM in one sorted stream, unread float to top
- Smart cards: Unread, Messages, Q&A, RFI, Supplier, DMs, Job, All
- Thread info: iMessage-style inline expandable (tap header inside thread), shows source context, escalation ladder, quick actions
- Escalation: bidirectional up AND down chain (Worker <-> Lead <-> Manager <-> Office)
- Attachments: photos, PDFs, part/PO/job references (tappable links), auto-save to job notebook, mobile offload 3mo, auto-delete 5yr
- JPO Hold threads show in BOTH JPO detail AND Channels page (dual-homed)
- Auto-fill job context when clocked in (program-wide rule)
- Real-time via sync engine (no polling)

### Notebooks (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-notebooks-pages.md`
**Files:** `IOSNotebooksListPage`, `IOSNotebookDetailPage`, `IOSJobNotebooksPage`, `IOSNotebookTemplatesPage`, `AddNotebookEntrySheet`, `CreateNotebookSheet`

**Key design decisions:**
- Hierarchy: Section Groups -> Sections -> Pages (OneNote-style)
- Block-based editing: each block = one type (text, heading, photo, checklist, etc.), Notion-style
- Sync conflicts: per-block resolution, AI merge with Apple AI glow, version comparison, manual rewrite option
- Shortcut commands: /h1, /h2, /checklist, /photo, /part, /panel, /divider, etc.
- Two to-do types: Regular Work + Warranty Work. Question is a tag (not separate type).
- Panel Schedule Builder: dedicated tool, drag-drop circuits, dual breakers, multiple panel types (MDP to 2-space disconnect), custom paper sizes, company header with drag-drop designer
- Daily Report: system-generated from clock/to-do data, AI compiled + self-verified, template-driven (Office configures), user adds notes below system section
- Templates: job starter templates, page templates, report templates, configurable per job type/status in Office

### People (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-people-pages.md`
**Files:** `IOSEmployeesPage`, `IOSEmployeeDetailPage`, `IOSCustomersPage`, `IOSCustomerDetailPage`, `IOSContractorsPage`, `IOSContractorDetailPage`, `IOSContactsPage`, `IOSHatsPage`, `IOSPermissionsPage`, `IOSTeamsPage`, `PeopleRouter`

**Key design decisions:**
- People Dashboard: working today, off today, certs expiring, team assignments
- Employee detail: hat visibility (employees see own hats read-only, managers can toggle), GRDB removal needed
- Customer detail: full page with contact info, additional contacts, business info, billing & payment (hat-gated), job history, communication history, documents, stats
- Payment tracking: company setting (enable/disable), green-to-red bar showing on-time %, overdue alerts
- Contractor detail: subcontractors get full ratings (quality/on-time/reliability), GC and contractors get notes only
- Contacts: unified list with active/inactive sections, smart cards by type, sort by recently updated
- Teams: full detail page with member management, job assignments, team stats

### Scheduling (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-scheduling-pages.md`
**Files:** `IOSScheduleCalendarPage`, `IOSDispatchPage`, `IOSTimeOffPage`, `IOSWeeklyAvailabilityPage`, `IOSSubSchedulePage`, `IOSDispatchTemplatesPage`, `IOSTemplateBuilderSheet`, `CreateScheduleEntrySheet`, `CreateDispatchSheet`, `RequestTimeOffSheet`

**Key design decisions:**
- Calendar: week + month views, half-day support
- Dispatch: drag-and-drop Gantt-style board, job stage shown, crew history (3mo), crew continuity tracking, time-off conflict popup
- Short-Term Pipeline: Start Anytime (target 3+), Schedule Needed (target 2+), Favorite GC (target 1+), Small Jobs pool
- Long-Term Pipeline: 3-year timeline view, capacity bars by month, callback tracking, bid tracking (simple)
- AI dispatch: 3 options with points-based reasoning, dedicated AI chat for modifications, learns from dispatcher picks
- Flex pool: unassigned jobs for self-assign (hat-gated), ready-to-start vs needs-contact types
- Capacity: work-days (person-days), based on historical job averages not estimates
- Job estimation questionnaire: grouped questions, stage-aware, "?" for unknowns, AI learns which questions matter
- Weekly reviews: delay factors, unanswered questions, on-track check
- End-of-job reviews: estimate vs actual, categorized delays, crew feedback, GC rating
- AI Smart Question System: suggests new questions after 15+ jobs, stage-specific, rejected questions log with AI reconsideration, history-based suggestions (GC/area/type)

### Tools (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-tools-pages.md`
**Files:** `IOSToolsDashboardPage`, `IOSToolRegistryPage`, `IOSToolCheckoutsPage`, `IOSToolMaintenancePage`, `IOSToolKitsPage`, `IOSToolAdminPage`, `IOSToolsRouter`

**Key design decisions:**
- Dashboard quick actions: pick action FIRST (Checkout/Return/Report Issue), then scan QR or type ID
- Tool detail: full checkout history, maintenance log, version history (2yr), attached parts
- Edit verification: any user can edit, but without hat → PENDING → manager notified → must scan QR to unlock approve/reject
- Four kit types: Consumable-Only, Tool+Consumable, Mixed, Tools-Only
- Kit features: missing tools status, inspection checklist, restock consumables, condition check on checkout AND return
- Tool trade: initiator condition check → request → receiver condition check → accept/decline. 7-day auto-complete if no response.
- Five maintenance types: time-based, usage-based, schedule-based, decreasing-based (confidence decay), condition-triggered
- Management page (renamed from Admin): bulk actions, categories/types config, company policies, location assignment, audit trail

### Fleet (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-fleet-pages.md`
**Files:** `IOSFleetDashboardPage`, `IOSVehiclesPage`, `IOSVehicleDetailPage`, `IOSMyTruckPage`, `IOSTruckToolsPage`, `IOSFuelPage`, `IOSMileagePage`, `IOSMaintenancePage`, `IOSInspectionsPage`, `IOSTelematicsPage`, `IOSTrailersPage`, `IOSTrailerDetailPage`, `IOSTrailerLocationsPage`, `IOSCreateVehicleSheet`, `IOSCreateTrailerSheet`, `IOSAssignDriverSheet`, `FleetRouter`

**Key design decisions:**
- My Vehicle = primary worker view, opens first for field workers, smart cards (Tools On Board, Parts On Board, Tank, Maintenance Due)
- Two truck inventory types: Truck Stock (permanent, MIN/TARGET/MAX) vs Transfer Area (temporary logistics)
- Trailers = mini warehouses with own shelves/drawers, own MIN/TARGET/MAX, AT SHOP uses target only, NOT AT SHOP uses full MIN/MAX
- Vehicle detail: 7 tabs (Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections)
- Pre-trip inspections: residential-sized checklist, customizable per vehicle/trailer type, ties into clock-in
- Fleet dashboard KPIs: smart cards for vehicles/active/maintenance due/overdue inspect/trailers/fuel/miles/cost
- Fleet reports live in Reports section (not Fleet)
- Code quality: cleanest section — zero GRDB imports, zero raw SQL, design enhancement only

### Reports (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-reports-pages.md`
**Files:** `IOSTimesheetsPage`, `IOSLaborOverviewPage`, `IOSPreBillingPage`, `IOSBookkeeperExportPage`, `IOSSpendingPage`, `IOSProfitabilityPage`, `IOSDailyReportsSummaryPage`, `IOSPublicReportView`, `IOSReportsRouter`

**Key design decisions:**
- Every report page gets smart cards, Export PDF + Export CSV toolbar buttons, help button, standard filter bar
- Standard filter bar (PROGRAM-WIDE): This Week, Last Week, This Period, Last Period, This Month, Custom + page-specific filters
- 15-minute rounding on timesheets: company setting, shows actual AND rounded side by side
- Report Builder (V1): pick type, pick fields, pick filters, generate — not a full BI tool
- Fleet reports (NEW): fuel costs, maintenance trends, mileage/cost per mile, vehicle utilization — live in Reports, not Fleet
- Warehouse reports (NEW): inventory value, backorders by supplier/brand, turnover rates
- Scheduling reports (NEW): crew utilization, dispatch efficiency, pipeline status
- Code quality: architecturally clean — zero GRDB imports, all using ReportsService, design enhancement only

### Office (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-office-pages.md`
**Files:** `IOSManageJobsPage`, `IOSSpendingDashboardPage`, `IOSWarehouseExecPage`, `IOSDeletionApprovalsPage`, `OfficePlaceholderView`, `OfficeRouter`

**Key design decisions:**
- Office = manager/admin command center, not a report viewer — surfaces decisions, approvals, oversight
- Dashboard daily briefing: smart cards (Approvals Pending, Working Today, JPOs Pending, Payment Overdue, Parts Below MIN, etc.), AI summary cached 1hr, push notification at 7 AM
- Priority color timeline (PROGRAM-WIDE): Green (ok), Yellow (4 days), Orange (24 hrs), Red (overdue), Gray (resolved)
- Unified approvals page: ALL approval types in one sorted queue (oldest first) — JPO, deletion, tool edit, warranty, schedule, time-off
- Spending summary: week-over-week AND month-over-month with trend arrows, full detail in Reports
- Office chat channel: auto-created for admin staff coordination, separate from job chats
- Other features: pending callbacks, expiring certs, insurance renewals, contract deadlines, audit confidence, overdue inspections, period close status, unread Q&A escalations
- Code quality: clean — no GRDB, all service-based, design enhancement only

### Settings (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-settings-pages.md`
**Files:** `AppConfigPage`, `ThemesPage`, `NotificationPrefsPage`, `CompanyProfilesPage`, `SyncPage`, `BluetoothPage`, `SecurityAdminPage`, `AuditLogPage`, `IOSAIConfigPage`, `IOSBackupsPage`, `IOSDataExportPage`, `IOSDatabaseResetPage`, `IOSDeviceManagementPage`, `IOSIntegrationsPage`, `IOSKeyManagementPage`, `IOSRemoteSyncPage`, `IOSSharedChannelsPage`, `IOSSupplierBridgePage`, `IOSUpdateProtocolPage`, `IOSBootstrapAdminPage`, `IOSClockOutQuestionsPage`, `PDFSettingsPage`, `BillingPayPage`, `AboutPage`, `SettingsRouter`

**Key design decisions:**
- Grouped navigation: 10 iOS-style groups (General, Company, Operations, Warehouse, Sync & Devices, Security, Data, AI & Integrations, Templates, Advanced)
- Settings search: iOS-style search at top, searches page names + key setting labels
- Sync scope classification: Company (🌐 syncs to all), Personal (👤 syncs to user's devices), Device (📱 never syncs)
- 11 new settings pages: Break/Lunch Policy, Tool Policies, Pre-Trip Checklists, Dispatch Preferences, Forecast Config, Organization Thresholds, Audit Settings, Daily Report Templates, Job Estimation Questions, Report Templates, Payment Tracking
- 5 simulated features made functional: Backups (real file I/O), Data Export (real CSV/JSON + share sheet), Update Check (real version comparison), AI Config (real Foundation Models detection), Sync Now (real sync attempt)
- Code quality: architecturally clean — no GRDB, all service-based, no bugs to fix, design enhancement and new pages only

---

## Completed Reviews — Orders (Prompts 26A-30E) — ALL DONE

### PO System (Prompts 26A-26F) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 26A | PO list cleanup: platform guard, count badges, date formatting, loadError guard |
| 26B | PO list swipe + sort: swipe actions with AI summary, sort options, awaiting delivery KPI |
| 26C | PO detail lifecycle: status-based actions (7 states), Drafting status, cancel confirmations |
| 26D | PO detail supplier CRM: supplier contact info, score bars, tabbed notes (PO + Supplier) |
| 26E | Parts Order Management: NEW page — supplier-centric cross-PO view, dual filters, multi-select actions |
| 26F | PO detail jobs + timeline: job grouping, delivery timeline bars, inline draft editing, receipt history |

### JPO System (Prompts 27A-27E) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 27A | JPO list cleanup: ActiveSheet, QR scan, count badges, Create JPO with clock auto-fill |
| 27B | JPO per-part status: migration (line_status + delivery_option), smart routing (stock → transfer vs approval) |
| 27C | JPO detail redesign: per-part approve/hold/reject, bulk actions, delivery options, PO linkage |
| 27D | JPO hold + chat: per-part chat thread, question prompt, auto-membership, chat indicator on list |
| 27E | Full audit trail: part_change_log table (migration 033), who-did-what logging, PartHistoryView component (cross-cutting) |

### Procurement (Prompts 28A-28D) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 28A | Procurement redesign: demand consolidation, stock logic, pull options, smart cards, bring-to-target buttons |
| 28B | Procurement suppliers: per-part supplier pick, cheapest/rated/fastest highlight, 2PM cutoff, split by JPO |
| 28C | Procurement PO preview: supplier-grouped preview, partial generation, save for later |
| 28D | Job stage planner: stage model (migration 034), category mapping, held/released parts, auto-release, stage settings |

### Orders Cleanup (Prompts 29A-29D) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 29A | Receiving fix: hardcoded user ID, ActiveSheet pattern, platform guard |
| 29B | Returns fix: ErrorStateView, console→UI errors, platform guard, smart cards |
| 29C | Approvals dashboard: smart cards, reject reason, actionError display, multi-type approvals |
| 29D | Orders cleanup: remove UnifiedOrderPage, update router tab order, consolidate SupplierPicker |

### JPO Creation (Prompts 30A-30E) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 30A | JPO creation layout: 3-panel (search/cart/suggestions), job auto-fill, delivery options, stock indicators |
| 30B | JPO creation search: AI-powered search (cart + last 5 context), QR scan, best match, internet toggle |
| 30C | JPO creation suggestions: companion rules (5) + AI picks (3), context switch on cart selection |
| 30D | JPO creation feedback: qty confirm dialog, companion points, ratio learning, AI→rule promotion |
| 30E | JPO creation submit: create JPO + lines, smart routing, replace IOSUnifiedOrderPage |

## Completed Reviews — Warehouse (Prompts 31A-31I) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 31A | Warehouse dashboard: remove GRDB, smart cards, fix quick actions, ActiveSheet, platform guard |
| 31B | Warehouse movements: remove GRDB, ActiveSheet, smart cards, platform guard |
| 31C | Warehouse locations: remove GRDB, action buttons in detail sheet, platform guard |
| 31D | Warehouse staging: swipe confirmation, batch clear, smart cards, platform guard |
| 31E | Warehouse receiving: start/continue session actions, smart cards, platform guard |
| 31F | Warehouse audit: fix setup stub, finalize/adjust actions, certainty tie-in TODO, platform guards |
| 31G | Warehouse inventory grid: location picker, group by type, low-stock styling, actions, smart cards |
| 31H | Warehouse returns+tools+network+settings: actions for display-only pages, remove dummy data, fix errors |
| 31I | Warehouse router: fix unknown route → ErrorStateView, verify all 11 routes |

## Completed Reviews — Cross-Cutting Cleanup (Prompts 32A-33H) — ALL DONE

### Navigation & Code Quality (Prompts 32A-32J) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 32A | Navigation restructure: sidebar order (daily→work→admin), tab reorder, People consolidation |
| 32B | Empty catch blocks: fix all empty catch {} and catch { print() } blocks |
| 32C | Guard without error: fix 42 files with guard-let-service that silently returns |
| 32D | Platform guards batch 1: remove #if os(iOS) from all Features/ files (~50 files) |
| 32E | Platform guards batch 2: remove #if os(iOS) from AI/Auth/App/Nav/Scanning/Sync/Shared (~57 files) |
| 32F | ActiveSheet conversion: convert 19 files from showXxx Bool to ActiveSheet enum |
| 32G | Print-to-state errors: replace print() error logging with UI state in 25+ files |
| 32H | Refreshable + searchable: add missing .refreshable and .searchable to 58 list pages |
| 32I | AI button dedup: remove duplicate AI toolbar buttons — one global button per page |
| 32J | Force unwrap + DispatchQueue: fix force unwraps in services, replace DispatchQueue with async/await |

### Feature Polish (Prompts 33A-33H) — ALL DONE

| Prompt | Feature |
|--------|---------|
| 33A | Help/Info buttons: PageHelpSheet component + help button on ALL pages (program standard) |
| 33B | Clock page fix: "no such column: address" SQL error + Lunch/Break/Supply Run buttons |
| 33C | JPO smart routing: stock-check-first flow for JPO line approval — transfer vs procurement |
| 33D | Procurement pull actions: wire pull option buttons to actual warehouse movements |
| 33E | PO detail placeholders: wire 6 "Coming Soon" stubs to real functionality |
| 33F | Receiving routing flow: 6-step condition check + smart routing (used/damaged/good) |
| 33G | Staging box management: physical box system — sizes, labels, full/open, contents, move-all |
| 33H | Duplicate wizard cleanup: delete inline wizard, use IOSMovementWizard (1364→369 lines) |

## Historical Prompt Chains — Originally Queued; Reconcile Against Results Log

### UI Quality Audit (Prompt 34A) — HISTORICAL LEDGER; VERIFY AGAINST RESULTS LOG / CURRENT QA

| Prompt | Feature |
|--------|---------|
| 34A | Sheet dismiss, sticky buttons, navigation links, data display, form validation |

### Targeted Fixes (Prompts 35A-35I) — HISTORICAL LEDGER; USE CURRENT ISSUE QUEUE FOR RESIDUALS

| Prompt | Feature |
|--------|---------|
| 35A | Daily report submit stubs: wire TODO buttons + remove service bypass + raw SQL |
| 35B | Job detail tab fixes: print() catches → state, client-side→server-side filtering, dead code |
| 35C | Scheduling raw SQL: IOSSubSchedulePage + IOSWeeklyAvailabilityPage GRDB removal |
| 35D | GeofenceAlertView fix: remove GRDB + raw SQL, fix silent clock-in/out errors |
| 35E | Fleet GRDB + ErrorStateView: remove GRDB from 2 pages, wire ErrorStateView in 6 pages |
| 35F | Audit session ID + PO delete nav: fix hardcoded session ID, navigate back after draft delete |
| 35G | Settings GRDB removal: remove GRDB + raw SQL from 10 Settings pages |
| 35H | Companion GRDB + hats delete: remove GRDB from 2 sheets, add hat delete confirmation |
| 35I | Reports + tools GRDB: remove GRDB from PreBilling, BookkeeperExport, ToolKits |

### Floor Plan System (Prompts 36A-36D) — LATER EVIDENCE EXISTS; MANUAL QA STILL REQUIRED

| Prompt | Feature |
|--------|---------|
| 36A | Floor plan migration: 7 tables (floor_plans, features, units, levels, areas, bins, assignments) + 15 service methods |
| 36B | Floor plan editor UI: grid view, drag-drop units, drill-in levels→areas→bins, sticker checklist |
| 36C | Floor plan navigation: warehouse GPS directions, QR scan full location view, user position tracking |
| 36D | Onboarding wizard: 6-step progressive setup, Quick Count mode, Save & Exit, AI suggestions |

### Audit Confidence System (Prompts 37A-37D) — LATER EVIDENCE EXISTS; MANUAL QA STILL REQUIRED

See `docs/plans/warehouse-audit-intelligence.md` for full design.

| Prompt | Feature |
|--------|---------|
| 37A | Audit confidence migration: 8 tables (confidence, sessions, counts, misplaced, user ratings, org ratings, consolidation) |
| 37B | Audit count tab UI: hidden counts, speed mode, misplaced cart, quick audit prompts, walking path queue |
| 37C | Organization tab: consolidation voting, org checklist, rating rollup area→unit→row→warehouse |
| 37D | User ratings + leaderboard: leaderboard for all, detail for managers, multi-user consensus, training suggestions |

### Break/Lunch Compliance (Prompts 38A-38B) — LATER EVIDENCE EXISTS; VERIFY CLOCK FLOW

| Prompt | Feature |
|--------|---------|
| 38A | 4-tier policy (state+company), break_records, auto-fill, 15-min rounding, state presets |
| 38B | Clock page buttons, settings page, clock-out questionnaire, bonus tracking |

### Hats Permission Audit (Prompt 39A) — LATER EVIDENCE EXISTS; VERIFY PERMISSIONS

| Prompt | Feature |
|--------|---------|
| 39A | Cross-cutting: replace hardcoded role checks with hasPermission(), seed new permission keys |

### Clock To-Do Integration (Prompts 40A-40B) — HISTORICAL LEDGER; VERIFY CLOCK WALKTHROUGH

| Prompt | Feature |
|--------|---------|
| 40A | Clock-in to-do picker, Mark Done + Pick Next, work type selector (New/Warranty) |
| 40B | Live elapsed timer, today's hours per job/to-do, Switch Job one-action button |

### Teams Detail (Prompt 41A) — LATER PEOPLE/TEAMS EVIDENCE EXISTS

| Prompt | Feature |
|--------|---------|
| 41A | IOSTeamDetailPage with members/roles/jobs, smart cards on list page, add/remove members |

### Chat (Prompts 42A-42D) — LATER RESULT EVIDENCE EXISTS; VERIFY CHAT/RFI/Q&A

| Prompt | Feature |
|--------|---------|
| 42A | Unified inbox: all message types, smart cards, unread badges, message preview |
| 42B | Thread info: iMessage-style expandable info panel, source context, escalation, quick actions |
| 42C | Attachments: photo/file/part-ref attachments, composer buttons, auto-save to job notebook |
| 42D | Q&A escalation: visual escalation ladder (Worker⇄Lead⇄Manager⇄Office), push back, smart cards |

### Notebooks (Prompts 43A-43E) — LATER RESULT EVIDENCE EXISTS; VERIFY EDITOR

| Prompt | Feature |
|--------|---------|
| 43A | Structure migration: section_groups, sections, block-based entries (9 types), hierarchy service |
| 43B | Detail rebuild: hierarchical layout, collapsible sections, block rendering, shortcut commands |
| 43C | Templates: job starter templates, page templates, template editor, "Create from Template" |
| 43D | Panel schedule: circuit grid, breaker types, 240V spanning, PDF export |
| 43E | Daily report system: auto-generated from clock/to-do data, AI verification, user notes, templates |

### People (Prompts 44A-44F) — LATER RESULT EVIDENCE EXISTS; VERIFY PRIVACY/PERMISSIONS

| Prompt | Feature |
|--------|---------|
| 44A | People dashboard: who's working (live), who's off, expiring certs, team assignments, smart cards |
| 44B | Employee detail rebuild: remove GRDB/raw SQL, service layer edits, hat visibility rules |
| 44C | Customer detail full: contacts, billing (hat-gated), job history, communication log, lifetime stats |
| 44D | Contractor detail: qualifications, rating (subs only), job history, notes, ActiveSheet fix |
| 44E | Contacts redesign: smart cards by type, active/inactive sections, sort options, type badges |
| 44F | Payment tracking: company setting, green-to-red status bar, overdue alerts, payment records |

### Jobs (Prompts 45A-45D) — LATER RESULT EVIDENCE EXISTS; VERIFY JOB/CLOCK FLOWS

| Prompt | Feature |
|--------|---------|
| 45A | Jobs list redesign: smart cards (8 statuses), AI summary, stage bar, dual progress, payment hold privacy |
| 45B | Job detail dashboard: overview tab as dashboard, metrics, AI summary, today's activity, quick actions, warranty |
| 45C | Job types & status: migration (warranty fields, continuous job, payment hold, clock-in blocking) |
| 45D | Warranty to-do: work classification (regular/warranty), manager review, reclassification tracking |

### Scheduling (Prompts 46A-46F) — LATER RESULT EVIDENCE EXISTS; VERIFY SCHEDULING UX

| Prompt | Feature |
|--------|---------|
| 46A | Scheduling calendar: month view, day dots/badges, tap detail, half-day scheduling (AM/PM) |
| 46B | Dispatch board: Gantt-style board, employee bars, half-day, unassigned pool, time-off conflicts |
| 46C | Short-term pipeline: Start Anytime/Schedule Needed/Favorite GC/Small Jobs, callback snooze, AI crew |
| 46D | Long-term pipeline: 3-year timeline, monthly capacity bars, bid tracker, AI capacity warnings |
| 46E | AI dispatch: 3 suggestions with points scoring, dedicated AI chat, learning from picks, early finish |
| 46F | Job estimation: questionnaire system, stage-aware, "?" unknowns, AI learning, capacity calc |

---

## Unreviewed Pages — What Still Needs Review

All feature areas have been reviewed and designed. No unreviewed areas remain.

---

## Common Issues Found Across Reviews

These patterns recur and should be checked on every page:

### Code Quality Issues (Fix These)
1. **`import GRDB` in UI files** — must use service layer, not raw SQL
2. **Multiple `.sheet()` modifiers** — only one per view, use `ActiveSheet` enum
3. **Missing error visibility** — `loadError` state + `ErrorStateView` UI display in every page
4. **`#if os(iOS)` / `#elseif os(macOS)` guards** — app is iOS-only, remove
5. **Missing delete confirmations** — every delete needs `.alert` confirmation
6. **Missing save/edit error feedback** — form sheets need `saveError` + `isSaving` state
7. **Missing `.refreshable`** — every list should support pull-to-refresh
8. **Missing `.searchable`** — lists with 10+ items need search
9. **Hardcoded zero counts** — badges showing 0 instead of querying real data
10. **No AI integration** — each page should post context notifications for the AI panel
11. **Empty catch blocks** — all catches must set error state, not print() or ignore
12. **Guard-let-service silent returns** — must set loadError when service init fails
13. **Force unwraps** — use safe optionals, never force unwrap
14. **DispatchQueue.main.asyncAfter** — use async/await instead

### Program-Wide Standards (ALL Pages Must Have These)
15. **Smart cards as filters** — stat card filters replace horizontal chip bars on ALL list pages
16. **Help/Info button** — every page gets a toolbar help button using `PageHelpSheet`
17. **Standard filter bar on date-relevant pages** — This Week / Last Week / This Period / Last Period / This Month / Custom
18. **Priority color timeline** — Green (ok), Yellow (4 days), Orange (24 hrs), Red (overdue), Gray (resolved)
19. **44px touch targets** — all tappable elements use `.frame(minHeight: 44)`
20. **One AI button per page** — bottom right floating orange circle, no duplicate toolbar buttons
21. **Full audit trail on ALL parts** — `part_change_log` table via `PartHistoryView`
22. **Hat-based permissions** — use `hasPermission()`, NEVER hardcode role names
23. **Auto-fill job context when clocked in** — all relevant forms auto-fill with current job context
24. **Block-based sync for notebooks** — per-block conflict resolution with AI merge

---

## Implementation Order

The prompt chains should be implemented in this order (dependencies flow downward):

```
DONE:  01-05 (foundation) → 06-10 (CRUD + security)
DONE:  11A-C (brands-suppliers) → 12A-F (dashboard) → 13A-E (catalog) → 14A-G (categories)
DONE:  15A-C (brands+suppliers cleanup) → 16A-I (pricing full)
DONE:  17A-H (suppliers) → 18A (cleanup) → 19A-K (companions)
DONE:  20A-D (QR per-module) → 21A-B (QR labels) → 22A-C (supplier bridge) → 23A-H (forecasting)
DONE:  24A (import/export)
DONE:  26A-F (PO system) → 27A-E (JPO system) → 28A-D (procurement)
DONE:  29A-D (orders cleanup) → 30A-E (JPO creation)
DONE:  31A-I (warehouse full)
DONE:  32A-J (cross-cutting cleanup) → 33A-H (feature polish)

CURRENT FOLLOW-UP (2026-05-23):
  - Do not use this old order as the live implementation queue.
  - Check `xcode-ai/prompt-results-log.md` for implementation evidence after prompt groups 34A-67A.
  - Check `xcode-ai/fix-prompts/00-fix-order.md` for the live prompt queue. Active-looking prompt work: PE-046, PE-047, PE-048, PE-049, and PE-051.
  - Use `docs/testing/wei-1944-full-app-usability-verification-matrix.md` for current human-visible QA priority/order.

ALL 12 feature areas designed. 0 unreviewed.
```

---

*Last updated: 2026-05-23 for GH#649 / WEI-2005: reconciled historical prompt-ledger language with prompt-results-log evidence and linked current QA matrices.*
