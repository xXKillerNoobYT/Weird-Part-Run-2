# AUTO GO Metrics

> **Auto-maintained** by `/auto-go` STEP 7.
> Read by the weekly `loop-self-improve` meta-check (Sunday afternoon) to analyze trends and mutate the loop.
> **Do not edit** by hand — this is raw data for the self-improvement pass.

## Per-iteration rows

| date | iteration | area | check | status | findings | fixes_applied | tests_added | duration_sec | meta_checks_fired |
|------|-----------|------|-------|--------|----------|---------------|-------------|--------------|-------------------|
| 2026-04-18 | 2 | parts | C1b_plan_vs_code_drift_clean | done | 2 (stale issues #162 #163 open but fixed) | 2 (closed #162 #163) | 0 | ~600 | morning-recommender |
| 2026-04-18 | 3 | parts | C2b_github_issues_ingested | done | 5 (subsumed issues), 4 (prompts unqueued) | 5 (closed: #144 #100 #106 #99 #105), 4 (queued PE-046–049) | 0 | ~1080 | sunday-claude-md-improver |
| 2026-04-18 | 4 | parts | C3_hunt_fix_clean | done | 4 SQL bugs + 1 HIG issue | 5 (companion_rules deleted_at x3, COALESCE x2 SKU, j.deleted_at, .contentShape #246) | 10 (2 companion-rule, 4 PE-COLORS plan, 2 resolveGeneralLine, 2 addJPOLineItem) | ~900 | none |
| 2026-04-18 | 5 | parts | C4_tests_present + C5_tests_pass | done | 13 untested methods found | 1 service fix (recordCompanionFeedback FK bug, issue #250) | 18 (companion intelligence suite: applySkipPenalty×2, resetBlockedPair, getCompanionSuggestions×2, recordCompanionFeedback×2, getNextPollPreview×2, getTrainingQuestion, tracePartFromSupplier, logPartFieldChanges×2, calculateStyle/TypeCoOccurrence, runAutoDiscoveryCycle, getJobPartsForSandbox, getNextLevelCoOccurrences) | ~1200 | none |
| 2026-04-18 | 6 | parts | C6_build_warnings_zero | done | 3 parts warnings + 4 out-of-scope (2 tools, 3 scheduling treated as 1 issue group) | 3 parts fixes (redundant #require ×2, unused seedStock result) | 0 | ~300 | none |
| 2026-04-18 | 7 | parts | C7_ui_polish | in_progress | 1 Severity-2 finding | 1 fix (AddSupplierContactSheet dismiss safety) | 0 | ~300 | none |
| 2026-04-18 | 8 | parts | C13_automation_opportunities (Phase 2 implement) | done | 1 APPROVED recommendation from prior Q&A | 1 hook built (parts-sql-check.sh) + #255 closed + rejected recommendation removed | 0 | ~600 | github-issues-sync (first global run) |
| 2026-04-18 | 9 | parts | C7_ui_polish + C13 close-out | done | 1 Severity-2 finding (ForecastDetailSheet) | 1 dismiss-safety fix (commit 4759796) + C13 close-out (4 Q&As processed) | 0 | ~300 | none |
| 2026-04-18 | 10 | parts | C7b_dev_improvement_polish | done | 3 HIG/a11y findings (12 sheets w/o detents, 37 TextFields w/o kbd dismiss, 1 icon button w/o label) | 1 inline fix (accessibility label commit 3ac4c00) + #248 comment with parts-scoped audit | 0 | ~300 | none |
| 2026-04-18 | 11 | parts | C8_security_reviewed | done | 0 security findings (10 SQL interpolations verified safe) | security-review-tracker.md created | 0 | ~300 | none |
| 2026-04-18 | 12 | parts | C9_performance_reviewed | done | 0 perf findings (all 5 phases clean) | performance-review-tracker.md created | 0 | ~300 | none |
| 2026-04-18 | 13 | parts | C10_cross_platform_parity | done (N/A) | 1 structural finding — no Tauri/React side in repo | #257 filed for CLAUDE.md drift; tracker created | 0 | ~200 | none |
| 2026-04-18 | 14 | parts | C11_github_issues_resolved | done | 0 closable, 0 orphan (14 parts issues all tracked) | Verified each has plan/prompt/parent tracker reference | 0 | ~200 | none |
| 2026-04-18 | 15 | parts | C11b_process_gaps_clean | done | 1 throughput signal (4 Xcode prompts stalled ~12h, already tracked) | Memory noted for Sunday loop-self-improve watch | 0 | ~200 | none |
| 2026-04-18 | 16 | parts | C12_claude_md_reflects_area | done | 0 parts-specific drift (arch section drift in #257) | parts area GRADUATED — 17/17 checks green across 16 iterations | 0 | ~200 | github-issues-sync (4h pulse) |

## Area Graduation Log

| Area | Graduated | Iterations | Notable |
|---|---|---|---|
| parts | 2026-04-18 | 16 (iter 1–16) | First area through the full 17-check gauntlet. 3 CLAUDE.md improver sub-runs, 1 approved automation built (parts-sql-check hook), 4 dismiss-safety fixes, 1 FK bug fixed + test, 18+18 new tests, 4 GitHub issues filed. Bundled trackers: security-review, performance-review, cross-platform-qa now exist. |
| jobs | 2026-04-19 | 17 (iter 17 day 1 → iter 8 day 2) | Baseline-clean area: 1 dismiss-safety fix (CreateJobSupplierChannelSheet), 0 hunt-fix findings, 0 security findings, 0 perf findings, 0 test gaps (204/67 = 3× coverage). Demonstrates the "graduated-baseline" profile — short iterations, heavy use of memory writes, 2 automation recs filed (GRDB allowlist, label auto-tagger). 5 open GitHub issues (#45, #53, #69–71) all tracked, 0 closable. |

## Area: warehouse (in progress)

| date | iteration | area | check | status | findings | fixes_applied | tests_added | duration_sec | meta_checks_fired |
|------|-----------|------|-------|--------|----------|---------------|-------------|--------------|-------------------|
| 2026-04-19 | 9 | warehouse | C1_plan_complete | done | 0 gaps — 3 plans totaling 793 lines cover all sub-pages | — | 0 | ~90 | none |
| 2026-04-19 | 10 | warehouse | C1b_plan_vs_code_drift_clean | done | 6 code-but-not-planned files (WarehouseRouter, ReceivingRoutingFlow, 4 WizardStep levels) | Added "Unplanned Files" plan entries — 0 unresolved drift | 0 | ~180 | none |
| 2026-04-19 | 11 | warehouse | C2_qa_resolved | done | 0 warehouse-pending Q&A; meta github-sync noted #258 (settings/sync future work) | — | 0 | ~90 | github-sync |
| 2026-04-19 | 12 | warehouse | C2b_github_issues_ingested | done | 5 program-review trackers (#56, #74, #75, #88, #91); 0 new; #74 critical GRDB refactor verified complete | — | 0 | ~120 | none |
| 2026-04-19 | 13 | warehouse | C3_hunt_fix_clean | done | 0 findings (HUNT FIX iter 70 already converged today — 3 bugs fixed, `try?` remainders are legit display fallbacks) | — | 0 | ~120 | none |
| 2026-04-19 | 14 | warehouse | C4_tests_present | done | 0 untested (137 funcs / 195 tests = 1.4× coverage, 100% breadth) | — | 0 | ~120 | none |

## Area: jobs (graduated)

| date | iteration | area | check | status | findings | fixes_applied | tests_added | duration_sec | meta_checks_fired |
|------|-----------|------|-------|--------|----------|---------------|-------------|--------------|-------------------|
| 2026-04-18 | 17 | jobs | C1_plan_complete | done | 0 gaps — 3 plans + 1 archived | — | 0 | ~180 | none |
| 2026-04-18 | 18 | jobs | C1b_plan_vs_code_drift_clean | done | 0 drift — all 10 planned pages present, plan concepts implemented (43 grep hits) | — | 0 | ~120 | none |
| 2026-04-18 | 19 | jobs | C2_qa_resolved | done | 0 pending Q&A for jobs | — | 0 | ~60 | none |
| 2026-04-18 | 20 | jobs | C2b_github_issues_ingested | done | 3 jobs issues (all program-review parents) | — | 0 | ~60 | none |
| 2026-04-18 | 21 | jobs | C3_hunt_fix_clean | done | 0 bugs (jc.customer_id verified valid junction-table ref) | — | 0 | ~120 | none |
| 2026-04-18 | 22 | jobs | C4_tests_present | done | 0 untested methods (204 tests / 67 funcs = 3x coverage) | — | 0 | ~120 | end-of-day revise-claude-md |
| 2026-04-18 | 23 | jobs | C5_tests_pass | done | 1383/1383 passing (+34 from iter 5) | — | 0 | ~120 | none |
| 2026-04-18 | 24 | jobs | C6_build_warnings_zero | done | 0 jobs warnings (scheduling #251 + tools #252 out-of-scope) | — | 0 | ~60 | none |
| 2026-04-18 | 25 | jobs | C7_ui_polish | done | 1 real dismiss-safety fix + 1 false positive | 1 fix (CreateJobSupplierChannelSheet commit b102dfa) | 0 | ~120 | none |
| 2026-04-19 | 1 | jobs | C7b_dev_improvement_polish | done | 0 findings (jobs clean on force unwrap, fatalError, a11y) | — | 0 | ~180 | github-sync (morning + 4h pulse); morning-kickoff |
| 2026-04-19 | 2 | jobs | C8_security_reviewed | done | 0 security findings (SQL concat verified safe GRDB idiom) | — | 0 | ~120 | none |
| 2026-04-19 | 3 | jobs | C9_performance_reviewed | done | 0 perf findings (all 5 phases clean — 8 bounded SELECTs, no N+1, lightweight .onAppear, no retention risks) | — | 0 | ~120 | none |
| 2026-04-19 | 4 | jobs | C10_cross_platform_parity | done (N/A) | 0 findings (repo is iOS-only; #257 tracks CLAUDE.md drift) | tracker entry for jobs | 0 | ~60 | none |
| 2026-04-19 | 5 | jobs | C11_github_issues_resolved | done | 5 open (all tracked: #45 T1-08/09, #53 parent, #69/70/71 program-review), 0 closable, 0 orphan | Verified each has plan/tracker reference | 0 | ~120 | none |
| 2026-04-19 | 6 | jobs | C11b_process_gaps_clean | done | 0 gaps (0 pending Q&A, 0 active Xcode prompts, 0 DevTODOs for jobs) | — | 0 | ~90 | none |
| 2026-04-19 | 7 | jobs | C12_claude_md_reflects_area | done | 0 CLAUDE.md drift; 3 memory entries added (baseline profile, GRDB safe idiom, no-labels convention) | auto-go-memory.md jobs section populated | 0 | ~120 | none |
| 2026-04-19 | 8 | jobs → **GRADUATED** → warehouse | C13_automation_opportunities_reviewed | done | 2 new recs filed (GRDB allowlist, area-label auto-tagger) | 2 Q&A pending + 2 appendix entries | 0 | ~300 | none |

## Weekly Roll-ups (updated by loop-self-improve)

_(empty — first roll-up on first Sunday after install)_

## What loop-self-improve Looks For

- **Per-check yield** — findings per run per check type; low-yield checks demoted
- **Per-area velocity** — iterations to graduate an area; stalled areas flagged
- **Q&A latency** — time between question filed and answered; slow Q&A triggers "tighten questions" recommendation
- **Xcode-prompt latency** — time between prompt written and marked done; growing queue = throughput issue
- **Automation-recommendation uptake** — adopted / deferred / ignored ratios per category

Self-improvements are applied autonomously for safe changes (reordering, enabling/disabling checks, adding chained skills) and filed as Q&A for the user when larger (new areas, new routines, architecture).

| 2026-04-19 | 15 | warehouse | C5+C6+C7 | done | 2 findings (dismiss-safety gaps) | 2 applied (IOSAuditSetupView + WizardAddStorageUnitSheet) | 0 | ~450 | none |
| 2026-04-19 | 16 | warehouse | C7b | done | 4 findings (1 missing accessibilityLabel, 3 missing accessibilityHidden, 1 missing scrollDismissesKeyboard) | 5 applied | 0 | ~420 | none |
| 2026-04-19 | 17 | warehouse | C8_security_reviewed | done | 0 findings (M1/M3/M4/M10 clean; 1 setClauses.joined at :1702 = safe GRDB idiom per memory) | — | 0 | ~180 | none |
| 2026-04-19 | 18 | warehouse | C9 | done | 2 findings (batch atomicity bug #259, 11-query N+1 #260) | 0 (filed as issues) | 0 | ~380 | none |
| 2026-04-19 | 19 | warehouse | C10+C11+C11b+C12 | done | 0 findings (all checks clean) | 0 | 0 | ~320 | none |
| 2026-04-19 | 24 | scheduling | C3_hunt_fix_clean | done | 0 findings (SchedulingService + AIDispatchService clean; 70 deleted_at filters, 2 legit JSON try?; iOS scheduling files clean) | — | 0 | ~180 | none |
| 2026-04-19 | 41 | tools | C7b_dev_improvement_polish | done | 1 finding (IOSToolDetailPage missing scrollDismissesKeyboard) | 1 fix | 0 | ~150 | stale-lock-recovery |
| 2026-04-19 | 50 | inventory | C1_plan_complete | done | 0 gaps — 4 plans totaling 1,213 lines cover forecasting/wishlist/procurement/MIN-TARGET-MAX | — | 0 | ~120 | github-sync |
| 2026-04-19 | 52 | reports | C1_plan_complete | done | Plan thin (49 lines) vs 22 iOS files + 2 services; supplemented to 90 lines with file-mapping table + service API + current-status | Plan supplement | 0 | ~300 | revise-claude-md (end-of-day) |
| 2026-04-20 | 1 | parts (R2) | C1_plan_complete | done (morning kickoff) | 0 gaps — all 5 parts plans intact from round 1 | — | 0 | ~120 | Gate C + morning-recommender + github-sync |
| 2026-04-20 | 10 | jobs (R2) | C3_hunt_fix_clean | done | 0 regressions (85 deleted_at filters vs 70 on day 2 = stronger defense; jobs uses `status` not `is_active` → no is_active gap) | — | 0 | ~120 | none |
| 2026-04-20 | 16 | scheduling (R2) | C1_plan_complete | done | 0 gaps — 2 plans intact from R1 | — | 0 | ~60 | github-sync (10h stale) |
| 2026-04-20 | 20 | tools (R2) | C1_plan_complete | done | 0 gaps — ios-tools-pages.md at 105 lines (R1 supplement from iter 37-38) intact | — | 0 | ~60 | none |
| 2026-04-20 | 29 | parts (R3) | C1_plan_complete | done | 0 gaps — all 5 parts plans intact from R1 | — | 0 | ~60 | revise-claude-md (end-of-day, deferred to per-area memory) |
| 2026-04-21 | 33 | scheduling (R3) | C1_plan_complete | done | 0 gaps — 2 scheduling plans intact from R1 | — | 0 | ~60 | morning-recommender + github-sync |
| 2026-04-21 | 55 | orders (R4) | C1_plan_complete | done | 0 gaps — 5 orders plans intact from R1 | — | 0 | ~60 | none |
| 2026-04-21 | 58 | tools (R4) | C1_plan_complete | done | 0 gaps — tools plan intact; budget_mode active (1 tick/hr) | — | 0 | ~30 | budget-mode |

## 🎉 Second Full Rotation Complete (2026-04-20 22:50)

**R2 complete — all 14 areas graduated twice.** Additional findings surfaced in R2 vs R1:
- **is_active defense gaps on LIST paths** (R1 focused on CREATE paths). Running total across services: ~40+ gaps found in R2.
- **scrollDismissesKeyboard coverage** — warehouse R2 patched 21 files via Python regex (17 auto + 4 manual).
- **Accessibility fixes** — 10+ additional a11y annotations across areas.

**R3 begins at parts.** R3 hypothesis: should be mostly no-op — R2 captured the second-tier gaps, so R3 is pure regression-guard.

## First Full Rotation Complete (2026-04-20 08:45)

**🎉 ALL 14 AREAS GRADUATED IN FIRST ROTATION** — parts → jobs → warehouse → scheduling → orders → people → tools → vehicles → inventory → reports → notebooks → chat → settings → cross-cutting. Loop now begins round-2 validation pass starting at parts again. Total iterations: ~58 over 3 days (2026-04-18 through 2026-04-20).
| 2026-04-23 | 1 (day1) | tools | C1b | done | 1 doc error (31→30 methods); 3 ?? 0 anti-pattern fixes in orders callers | 3 | 0 | ~15min | github-issues-sync |
| 2026-04-24 | 1 (day1) | tools | C2+C2b | done | 0 pending Q&A for tools; 1 open issue (#58 parent tracker) | 0 | 0 | ~2min | none (deferred github-sync, recommender past window) |
| 2026-04-24 | 2 | tools | C3 | done | 3 FK-orphan gaps (ToolsService checkout/return/maintenance) — Sonnet sub-agent scan | 3 | 4 | ~8min | none |
| 2026-04-24 | 3 | tools | C4 | done | 0 missing-method gaps (30/30 covered before); 15 edge-case gaps filled | 0 | 15 | ~14min | github-issues-sync (4h+ pulse, 0 new) |
| 2026-04-24 | 4 | tools | C5 | done | 0 failures (111/111 ToolsServiceTests green) | 0 | 0 | ~10s | none |
| 2026-04-24 | 5 | tools | C6 | done | 0 build warnings (tools-scoped & global) | 0 | 0 | ~30s | none |
| 2026-04-24 | 6 | tools | C7 | done | 18 polish findings (10 dismiss-safety, 7 detents, 1 empty-state) — 1 inline fix, 17 deferred | 1 | 0 | ~6min | none |
