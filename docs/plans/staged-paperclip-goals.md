# Wired Parts Run 2 Staged Paperclip Goals

> Last updated: 2026-07-02 (beta completion pass — promotion table synced to live Paperclip goal statuses; GitHub sync register corrected)
> Authority: This is the staged execution index for Paperclip-managed programming work. It supersedes old "current phase" labels in historical plans when deciding what agents may start next.

## North Star

Wired Parts Run 2 should reach field-test readiness as a local-first iOS shop-management app with reliable identity, local data, inventory, jobs, procurement, scheduling, sync, and beta operations. The app remains offline-capable by default, plan-first in execution, and quality-gated before every promotion.

## Current Promotion State

| Stage | State | Execution rule |
|---|---|---|
| Stage 1 | Active | Shell/identity/local-DB/onboarding/navigation stabilization continues as maintenance (dead-end routes eliminated 2026-07-02, GH #1338). |
| Stages 2-4 | **Achieved** (per live Paperclip goals) | Bug fixes and maintenance proceed as GitHub issues; no promotion gate needed for fixes to achieved stages. |
| Stage 5 | **Active** (per live Paperclip goals) | Time/hours/breaks/timesheets — #435/#436 re-landed + break-compliance day-hours fix, 2026-07-02. |
| Stages 6-11 | Planned | Agents may plan, clarify, file blockers, and prepare backlog handles. Implementation starts when Isaac/Paperclip promotes the stage — except explicit GitHub issues, which are always actionable work per the issues-ledger goal. |
| Non-primary projects | Planning-only | Keep reusable guidance and dependency notes, but do not pull execution focus away from Wired Parts Run 2 unless they unblock it. |

Promotion requires an issue-thread decision or approved plan revision that names the new active stage, confirms blockers from earlier stages are closed or consciously deferred, and states the validation gate for the next stage.

## Backdown Review and Priority Order

The plan is ordered from most useful to least useful for field-test readiness. Each row names whether it is required for later work or a lower-priority improvement.

Legend:

- `[R]` Required dependency. This must work before the named later workflow can be trusted.
- `[H]` High priority after required dependencies. It may not block every screen, but it is important enough to schedule early.
- `[N]` Nice-to-have or polish. Do not start until required dependencies above it are working or explicitly deferred.

| Priority | Type | Area | Why it is ordered here | Depends on | Enables |
|---|---|---|---|---|---|
| 1 | `[R]` | App shell, identity, local DB, onboarding, navigation | Users must be able to open the app, identify themselves, keep local data, and reach each primary area. | None | Every other workflow. |
| 2 | `[R]` | Parts categories, catalog hierarchy, part identity | Parts need stable categories/types/colors/brands before inventory, purchasing, job material usage, pricing, and reports can be meaningful. | Stage 1 | Inventory tracking, procurement, job material tracking, report export. |
| 3 | `[R]` | Inventory tracking and basic warehouse locations | Operators need current stock, minimum/target/max quantities, movement history, and simple location records before they can trust orders or job pulls. | Stages 1-2 | Reorder decisions, JPO/PO receiving, job material allocation, warehouse reports. |
| 4 | `[R]` | Job tracking, labor, clock, daily reports | Jobs are the field work unit. Labor, daily reports, notebooks, and material usage need reliable job records. | Stage 1 and parts/inventory references from Stages 2-3 | Job reports, scheduling, procurement by job, payroll/time review. |
| 5 | `[H]` | Reports and export baseline | Board priority: exporting reports is high priority. Reports need early visibility once the core data they summarize exists. | Stages 2-4 for useful source data | PDF/CSV/share workflows for parts, inventory, jobs, labor, and daily reports. |
| 6 | `[R]` | Procurement, JPO/PO, receiving, staging, pricing, import/export | Purchasing must be downstream of parts and inventory, otherwise orders and pricing drift. Import/export for operational data belongs here after source models are stable. | Stages 2-5 | Office purchasing, receiving, cost control, supplier workflows. |
| 7 | `[H]` | Scheduling, dispatch, people, approvals, time workflows | Scheduling and dispatch are important, but they become reliable only after jobs, people identity, and time records are sound. | Stages 1 and 4 | Crew assignment, approval queues, office coordination. |
| 8 | `[R]` | Local-first sync, security, encryption, data correctness | Once core workflows hold real data, sync and security become release blockers. They must be hardened before broad field-test expansion. | Stages 1-7 source models | Safe multi-device use, protected local storage, trustworthy offline behavior. |
| 9 | `[H]` | QA automation, beta hardening, release readiness, deployment | Validation and release packaging follow the main workflow buildout but gate any field-test release. | Stages 1-8 | TestFlight/direct distribution, rollback/update protocol, release confidence. |
| 10 | `[N]` | Floor plans, visual shop storage system, AI/help, cross-project reuse | Useful polish and long-term leverage, but lower than categories, inventory, jobs, reports, and data safety. Basic locations remain Stage 3; visual floor-plan placement waits here unless promoted. | Stages 1-9, or explicit board promotion | Spatial warehouse UX, contextual assistance, reusable standards. |

If a plan file or issue is ambiguous about priority, create a Paperclip issue assigned to the board that names the page/plan, quotes the unclear section, and asks for a priority listing before implementation starts.

## Operating Rules

- Plans before prompts: design decisions go in `docs/plans/` before Xcode AI prompts or implementation work.
- Owner approval: xXKillerNoobYT-owned repos may proceed with Isaac/Paperclip approval. External-owner repos require a dedicated plan branch and explicit owner approval before code changes.
- Branch hygiene: check remote branches, open PRs, registered worktrees, and prunable worktrees before starting new Weird Parts coding work.
- Environment cap: do not create broad duplicate local environments; stay under the 180 GB environment cap and prefer existing worktrees.
- Quality gates: code work must keep tests, review, branch hygiene, accessibility/responsive expectations, and security checks intact.
- Historical plans stay as history: archive files and old phase labels remain useful background, but this staged index decides execution order.

## Stage Dependency Map

Each stage depends on the earlier stages unless the issue thread explicitly records a narrower exception.

| Stage | Goal | Primary docs | Durable handles | Acceptance criteria | Blockers and notes |
|---|---|---|---|---|---|
| 1 | Stabilize app shell, identity, local DB, onboarding, and navigation | `CLAUDE.md`; `docs/paperclip-handoff.md`; `docs/plans/ios-foundation-fixes.md`; `docs/plans/ios-fresh-install-resilience.md`; `docs/plans/ios-settings-pages.md`; `docs/plans/login-ax5-keyboard-overlap-fix.md` | Paperclip: `WEI-2685`, `WEI-2687`, `WEI-2688`. GitHub: repo access currently unavailable in this heartbeat; use this stage row until GitHub sync is restored. | Fresh install reaches usable navigation; identity/auth flows are reliable; local database migrations bootstrap without destructive resets; onboarding does not trap users; shell navigation has no dead primary routes. | Active stage. Do not promote Stage 2 until Stage 1 smoke evidence is attached or consciously deferred by Isaac/Paperclip. |
| 2 | Parts categories, catalog hierarchy, and part identity | `docs/plans/parts-section-audit-fix-plan.md`; `docs/plans/ios-catalog-page.md`; `docs/plans/ios-categories-page.md`; `docs/plans/colors-parts-redesign.md`; `docs/plans/ios-part-number-hierarchy.md` | GitHub: #237-#240 for PE-COLORS; #645 for construction parts expansion. Backlog handle: Stage 2 row in this document. | Categories, styles, types, colors, brands, suppliers, part numbers, search/filter, and safe category edits work without orphaning inventory or orders. | Planned. `[R]` Must be done before inventory tracking, procurement, job material usage, pricing, and reports can be trusted. |
| 3 | Inventory tracking and basic warehouse/location baseline | `docs/plans/inventory-intelligence-system.md`; `docs/plans/ios-warehouse-pages.md`; `docs/plans/warehouse-audit-intelligence.md`; `docs/plans/ios-import-export-page.md`; `docs/plans/pre-release-testing-checklist.md` | Backlog handle: Stage 3 row in this document. | Stock counts, min/target/max thresholds, movement history, simple storage/location records, warehouse audit, and inventory import/export work with real data and no silent loss. | Planned. `[R]` Requires Stage 2 parts identity. Visual floor plans and drag placement are lower priority Stage 10 work unless the board promotes them. |
| 4 | Jobs, labor, daily reports, and notebooks | `docs/plans/ios-jobs-pages.md`; `docs/plans/ios-clock-page-redesign.md`; `docs/plans/ios-notebooks-pages.md`; `docs/plans/ios-page-review-tracker.md`; `docs/plans/master-issue-list.md` | GitHub: existing job-stage work is represented by completed prompt 60S and related issue history in `xcode-ai/fix-prompts/done/60S-job-stage-bars.md`. Backlog handle: Stage 4 row in this document. | Active job list, job detail, clock in/out, labor totals, daily reports, notebook, and stage-aware job flows work as one coherent field workflow. | Planned. `[R]` Requires Stage 1 navigation and references Stage 2-3 parts/inventory for material workflows. |
| 5 | Reports and export baseline | `docs/plans/ios-reports-pages.md`; `docs/plans/ios-page-review-tracker.md`; `docs/plans/pre-release-testing-checklist.md`; `docs/TESTING-REQUIREMENTS.md`; `docs/plans/ios-import-export-page.md` | Backlog handle: Stage 5 row in this document. | Users can export useful parts, inventory, job, labor, and daily-report outputs as appropriate for field review, office review, and customer/vendor handoff. Export failures are visible and recoverable. | Planned. `[H]` Board marked report exporting high priority. Requires Stages 2-4 for meaningful data, then should run before lower-priority polish. |
| 6 | Procurement, JPO/PO, receiving, staging, pricing, operational import/export | `docs/plans/ios-jpo-page.md`; `docs/plans/ios-jpo-creation-page.md`; `docs/plans/ios-purchase-orders-page.md`; `docs/plans/ios-procurement-page.md`; `docs/plans/ios-receiving-draft-persistence.md`; `docs/plans/ios-pricing-system.md`; `docs/plans/ios-import-export-page.md` | GitHub: `docs/plans/master-issue-list.md` tracks T1-03, T1-11, T1-12, T1-13, T1-15 and related prompt order. Backlog handle: Stage 6 row in this document. | Field requests convert into office purchasing and receiving without empty orders, misleading supplier actions, data loss, or pricing/import/export drift. | Planned. `[R]` Depends on Stage 2 parts, Stage 3 inventory, Stage 4 jobs, and Stage 5 export visibility for operational review. |
| 7 | Scheduling, dispatch, people, approvals, and time workflows | `docs/plans/ios-scheduling-pages.md`; `docs/plans/ios-people-pages.md`; `docs/plans/ios-office-pages.md`; `docs/plans/ios-hat-assignment-ux.md`; `docs/plans/ios-clock-fix.md` | GitHub: `docs/plans/master-issue-list.md` tracks T1-04, T1-05, T1-06, T1-07 and related schedule/dispatch gaps. Backlog handle: Stage 7 row in this document. | Office and field users can schedule, dispatch, manage people, approve work, and handle time flows with clear permissions and no dead interactions. | Planned. `[H]` Depends on Stage 4 jobs/labor and Stage 1 identity. |
| 8 | Local-first sync, security, encryption, and data correctness | `docs/plans/sync-field-timestamps-upgrade.md`; `docs/plans/pagination-cutover.md`; `docs/plans/email-encryption-sqlcipher.md`; `docs/plans/phase-13-sync-bluetooth.md`; `docs/plans/security-review.md` | GitHub: #221 per-field LWW timestamps; #227 pagination cursor cutover; PR #320 SQLCipher whole-DB migration; CodeQL issue family #292/#294/#296/#298/#303. | Sync conflicts do not lose data; security-sensitive storage is encrypted; pagination is explicit; device trust and local-first constraints are documented and testable. | Planned. `[R]` Becomes a release blocker once Stages 2-7 hold real operational data. Security-sensitive implementation may need a dedicated security owner and explicit review. |
| 9 | QA automation, beta hardening, release readiness, and deployment | `docs/plans/testing-strategy.md`; `docs/plans/pre-release-testing-checklist.md`; `docs/plans/pre-release-audit-results.md`; `docs/plans/hunt-fix-verify-loop.md`; `docs/dev-pipeline.md`; `docs/plans/deployment-master-plan.md`; `docs/RELEASE-READINESS-CHECKLIST.md`; `docs/plans/production-readiness.md`; `docs/plans/sideloading-guide.md` | GitHub: #143 dismiss-safety campaign; #257 architecture-doc drift; scanner issues #327, #328, #340, #342, #344, #345. Deployment handles are recorded in `docs/github-branch-matrix-2026-05-09.md`. Backlog handle: Stage 9 row in this document. | Tests and scanners are current; stale branch/worktree cleanup is tracked; signed builds are reproducible; release checklist is green; rollback/update protocol is understood. | Planned. `[H]` Runs continuously as a gate, but broad release campaigns wait until earlier required stages are stable. |
| 10 | Floor plans, visual shop storage, AI/help, cross-project reuse, and future expansion | `docs/plans/phase-16-ux-polish-and-admin-hub.md`; `docs/plans/ai-assistant-plan.md`; `docs/plans/apple-foundation-models-integration.md`; `docs/plans/ios-chat-pages.md`; `docs/testing/ai-page-context-coverage.md`; `docs/plans/empty-state-help-link-taxonomy.md`; `docs/plans/construction-parts-expansion-roadmap.md`; `docs/plans/companion-rules-system.md`; `docs/plans/supplier-communication-bridge-plan.md`; `docs/plans/phase-15-remote-sync.md` | GitHub: #645 construction parts expansion. Backlog handle: Stage 10 row in this document. | Visual floor plans and storage placement improve warehouse usability; AI/help improves guidance; reusable standards are documented without activating secondary-project implementation. | Planned. `[N]` Basic storage/location records are Stage 3; visual floor plans and AI/cross-project work wait until required beta workflows are stable or the board explicitly promotes them. |

## GitHub Sync Register

GitHub access is restored and healthy (verified 2026-07-02: `gh` resolves `xXKillerNoobYT/Weird-Part-Run-2`, issues/PRs sync normally, Paperclip Tracker Sync workflow green). GitHub issues are the live backlog handles; the fallback note below is historical.

*Historical note (2026-05): during WEI-2687 both `gh` paths and the Paperclip GitHub app lacked repository visibility, so this document temporarily served as the durable backlog handle.*
