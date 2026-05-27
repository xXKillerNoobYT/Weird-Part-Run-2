# Wired Parts Run 2 Staged Paperclip Goals

> Last updated: 2026-05-26
> Authority: This is the staged execution index for Paperclip-managed programming work. It supersedes old "current phase" labels in historical plans when deciding what agents may start next.

## North Star

Wired Parts Run 2 should reach field-test readiness as a local-first iOS shop-management app with reliable identity, local data, inventory, jobs, procurement, scheduling, sync, and beta operations. The app remains offline-capable by default, plan-first in execution, and quality-gated before every promotion.

## Current Promotion State

| Stage | State | Execution rule |
|---|---|---|
| Stage 1 | Active | Agents may execute bounded implementation and cleanup that stabilizes the shell, identity, local database, onboarding, and navigation. |
| Stages 2-10 | Planned | Agents may plan, clarify, file blockers, and prepare backlog handles only. Implementation starts only after Isaac/Paperclip explicitly promotes the stage. |
| Non-primary projects | Planning-only | Keep reusable guidance and dependency notes, but do not pull execution focus away from Wired Parts Run 2 unless they unblock it. |

Promotion requires an issue-thread decision or approved plan revision that names the new active stage, confirms blockers from earlier stages are closed or consciously deferred, and states the validation gate for the next stage.

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
| 2 | Parts, catalog, inventory, and warehouse baseline | `docs/plans/inventory-intelligence-system.md`; `docs/plans/ios-catalog-page.md`; `docs/plans/ios-categories-page.md`; `docs/plans/ios-warehouse-pages.md`; `docs/plans/warehouse-audit-intelligence.md`; `docs/plans/colors-parts-redesign.md` | GitHub: #237-#240 for PE-COLORS; #645 for construction parts expansion. Backlog handle: Stage 2 row in this document. | Core parts hierarchy, catalog, stock views, warehouse setup, and audit flows support field use without fake data or silent failures. | Planned. Stage 1 shell and DB reliability come first. |
| 3 | Jobs, labor, daily reports, and notebooks | `docs/plans/ios-jobs-pages.md`; `docs/plans/ios-clock-page-redesign.md`; `docs/plans/ios-notebooks-pages.md`; `docs/plans/ios-page-review-tracker.md`; `docs/plans/master-issue-list.md` | GitHub: existing job-stage work is represented by completed prompt 60S and related issue history in `xcode-ai/fix-prompts/done/60S-job-stage-bars.md`. Backlog handle: Stage 3 row in this document. | Active job list, job detail, clock in/out, daily report, notebook, and stage-aware job flows work as one coherent field workflow. | Planned. Requires Stage 1 navigation and identity stability. |
| 4 | Procurement, JPO/PO, receiving, staging, pricing, import/export | `docs/plans/ios-jpo-page.md`; `docs/plans/ios-jpo-creation-page.md`; `docs/plans/ios-purchase-orders-page.md`; `docs/plans/ios-procurement-page.md`; `docs/plans/ios-receiving-draft-persistence.md`; `docs/plans/ios-pricing-system.md`; `docs/plans/ios-import-export-page.md` | GitHub: `docs/plans/master-issue-list.md` tracks T1-03, T1-11, T1-12, T1-13, T1-15 and related prompt order. Backlog handle: Stage 4 row in this document. | Field requests convert into office purchasing and receiving without empty orders, misleading supplier actions, data loss, or pricing/import/export drift. | Planned. Depends on Stage 2 parts and warehouse baseline. |
| 5 | Scheduling, dispatch, people, approvals, and time workflows | `docs/plans/ios-scheduling-pages.md`; `docs/plans/ios-people-pages.md`; `docs/plans/ios-office-pages.md`; `docs/plans/ios-hat-assignment-ux.md`; `docs/plans/ios-clock-fix.md` | GitHub: `docs/plans/master-issue-list.md` tracks T1-04, T1-05, T1-06, T1-07 and related schedule/dispatch gaps. Backlog handle: Stage 5 row in this document. | Office and field users can schedule, dispatch, manage people, approve work, and handle time flows with clear permissions and no dead interactions. | Planned. Depends on Stage 3 jobs/labor and Stage 1 identity. |
| 6 | Local-first sync, security, encryption, and data correctness | `docs/plans/sync-field-timestamps-upgrade.md`; `docs/plans/pagination-cutover.md`; `docs/plans/email-encryption-sqlcipher.md`; `docs/plans/phase-13-sync-bluetooth.md`; `docs/plans/security-review.md` | GitHub: #221 per-field LWW timestamps; #227 pagination cursor cutover; PR #320 SQLCipher whole-DB migration; CodeQL issue family #292/#294/#296/#298/#303. | Sync conflicts do not lose data; security-sensitive storage is encrypted; pagination is explicit; device trust and local-first constraints are documented and testable. | Planned. Security-sensitive implementation may need a dedicated security owner and explicit review. |
| 7 | Reliability, QA automation, issue hygiene, and beta-hardening gates | `docs/plans/testing-strategy.md`; `docs/plans/pre-release-testing-checklist.md`; `docs/plans/pre-release-audit-results.md`; `docs/plans/hunt-fix-verify-loop.md`; `docs/dev-pipeline.md`; `docs/github-branch-matrix-2026-05-09.md` | GitHub: #143 dismiss-safety campaign; #257 architecture-doc drift; scanner issues #327, #328, #340, #342, #344, #345. | Tests and scanners are current; open issues have owners or deferral reasons; stale branch/worktree cleanup is tracked; beta readiness evidence exists. | Planned. Runs continuously as a gate, but broad beta-hardening campaigns wait until earlier stages are stable. |
| 8 | AI, help, contextual guidance, and page context | `docs/plans/ai-assistant-plan.md`; `docs/plans/apple-foundation-models-integration.md`; `docs/plans/ios-chat-pages.md`; `docs/testing/ai-page-context-coverage.md`; `docs/plans/empty-state-help-link-taxonomy.md` | GitHub: `docs/plans/master-issue-list.md` tracks T1-18, T1-19, T1-20 and T2-23 through T2-25. Backlog handle: Stage 8 row in this document. | AI/help remembers conversation context where required, receives page context, and improves workflows without replacing explicit user control. | Planned. Do not let AI work preempt data correctness or beta-blocking reliability. |
| 9 | Deployment, packaging, release readiness, and field-test operations | `docs/plans/deployment-master-plan.md`; `docs/RELEASE-READINESS-CHECKLIST.md`; `docs/plans/production-readiness.md`; `docs/plans/sideloading-guide.md`; `docs/plans/Mobile device bootstrap.md` | GitHub: deployment PR/issue handles are recorded in `docs/github-branch-matrix-2026-05-09.md`; backlog handle: Stage 9 row in this document. | TestFlight/direct distribution path is documented, signed builds are reproducible, release checklist is green, and rollback/update protocol is understood. | Planned. Depends on Stage 6 data safety and Stage 7 beta-hardening evidence. |
| 10 | Cross-project reuse, non-primary project governance, and future expansion | `docs/plans/construction-parts-expansion-roadmap.md`; `docs/plans/companion-rules-system.md`; `docs/plans/supplier-communication-bridge-plan.md`; `docs/plans/phase-15-remote-sync.md`; `docs/plans/phase-16-ux-polish-and-admin-hub.md` | GitHub: #645 construction parts expansion. Backlog handle: Stage 10 row in this document. | Reusable standards are documented without activating secondary-project implementation; expansion work has explicit owner approval, dependencies, and promotion criteria. | Planned. Never steals active focus from Wired Parts Run 2 unless Isaac/Paperclip promotes it or names it as an unblocker. |

## GitHub Sync Register

GitHub issue creation/update was attempted during WEI-2687, but both available paths lacked repository visibility:

- Local `gh` could not resolve `Weirdtoo/Weird-Part-Run-2` from the current remote.
- Local `gh` could not resolve the historical `xXKillerNoobYT/Weird-Part-Run-2` repository recorded in the handoff.
- The Paperclip GitHub app returned zero accessible repositories.

Until GitHub access is restored, this document is the durable backlog handle for any stage row that does not list a live GitHub issue. When access is restored, create or update GitHub issues for stages that still only have this document as their handle, then replace those fallback notes with issue URLs.

## Promotion Checklist

Before any stage changes from planned to active:

1. Confirm the previous active stage is done, explicitly deferred, or blocked with a named owner/action.
2. Update this document with the new state and any changed dependencies.
3. Link or create GitHub/Paperclip issue handles for the promoted stage.
4. Record acceptance criteria, required evidence, and review lane on the issue.
5. Re-run branch/worktree hygiene preflight before assigning implementation.
