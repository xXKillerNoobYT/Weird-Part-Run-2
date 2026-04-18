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

## Weekly Roll-ups (updated by loop-self-improve)

_(empty — first roll-up on first Sunday after install)_

## What loop-self-improve Looks For

- **Per-check yield** — findings per run per check type; low-yield checks demoted
- **Per-area velocity** — iterations to graduate an area; stalled areas flagged
- **Q&A latency** — time between question filed and answered; slow Q&A triggers "tighten questions" recommendation
- **Xcode-prompt latency** — time between prompt written and marked done; growing queue = throughput issue
- **Automation-recommendation uptake** — adopted / deferred / ignored ratios per category

Self-improvements are applied autonomously for safe changes (reordering, enabling/disabling checks, adding chained skills) and filed as Q&A for the user when larger (new areas, new routines, architecture).
