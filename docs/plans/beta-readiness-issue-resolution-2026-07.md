# Beta-Readiness Issue-Resolution Plan — xXKillerNoobYT/Weird-Part-Run-2
*Synthesized 2026-07-01 from issue triage (80 issues), PR audit (#1343–#1346), CI audit, branch audit, and hygiene audit.*

---

## 1. SCOREBOARD

| Classification | Count |
|---|---|
| **valid** (needs code work) | 50 |
| **already-fixed** (close now) | 18 |
| **tracker-parent** (umbrellas — 2 closable now, 7 stay open) | 9 |
| **owner-decision** | 3 |
| **Total triaged** | **80** |

**Beta-blockers:** 22 valid issues are beta-blockers, plus 4 beta-blocking tracker-parents (#98, #90, #84, #83) that close when their children re-land. Concentration by goal area: parts catalog/pricing (7), parts tracking/scanning/warehouse (7), JPO/PO (5), job tracking (1), time tracking (2), notebooks (2), plus 3 cross-cutting P0/P1 umbrellas already covered by open PRs #1343/#1344/#1346.

**Fast wins already in flight:** 4 open PRs (#1343–#1346) resolve 4 of the top 6 umbrella issues (#1334–#1337). None mergeable as-is; exact unblock steps in §5.

---

## 2. CLOSE NOW (20 issues — post evidence comment, close)

| # | Evidence one-liner |
|---|---|
| #1190 | PR #1270 (97de096bc) added receive-shipment different-price validation — completeReceiving now blocks with inline errors per acceptance criteria. |
| #858 | DashboardService.swift:645-661 sums break_records per spec (PR #916); `swift test --filter DashboardServiceTests` passes 57/57 on main — the 06-30 reopen was a stale PR #1170 workspace. |
| #744 | `docs/Problomes ` trailing-space dir removed by junk purge df1b3eb26 (PR #1340); find returns 0 files for both spellings. |
| #738 | PR #728 reconstructed/merged as 4b081dfac (2 files only); `git ls-files` shows 0 tracked `.paperclip/` paths. |
| #726 | Import parser (PartsService.swift:6403-6407) now rejects blank category with "Missing required category" preview error (commit a84e37631, PR #938). |
| #645 | docs/plans/construction-parts-expansion-roadmap.md merged via PR #652; all acceptance criteria met per the issue's own handoff comment. |
| #596 | 11 of 12 listed PRs merged 2026-05-22/23, #502 closed; only 4 PRs open today — the backlog no longer exists. |
| #499 | IOSMainView.swift:913-946 uses ScrollViewReader + proxy.scrollTo(selectedTabId) on appear/change (commit 57e3a2fc5, PR #816). |
| #496 | PR #815 added deterministic fixtures: AppCore.swift:1501-1546 UITesting states + both WEI936 UI tests on main. |
| #493 | PR #812 (6f9d62db0) — IOSVerificationSubmitSheet.swift:105 has the exact required "already submitted" copy; old copy gone from repo. |
| #488 | Compile break never reached main: single declaration + single .sheet(item:) in IOSAuditPage.swift; `swiftc -parse` clean. |
| #480 | WarehouseDashboardPage.swift:629-685 exposes whAction_* identifiers/labels (PR #621); issue's own final comment reports regression test 1/1 passing. |
| #279 | PR #630 replaced isLoading antipattern in all six named Fleet pages; file trivial follow-up for the 3 out-of-scope files (Telematics/TrailerLocations/TruckTools) in the polish batch (B14). |
| #87 | WEI-427 closeout verified full PO-lifecycle checklist; awaiting-delivery KPI/chips, PODetailPage, DeliveryTimelineBar all on main; residual bugs tracked separately (#1190 now also fixed). |
| #73 | Last blocker #371 fixed — OrdersService.swift:2683/3018 set line_status='in_procurement'; wishlist/forecast demand live in IOSProcurementPage. |
| #72 | WEI-441 verified all 11 markers; IOSJPOCreationPage.swift:121-135 has the 3-panel responsive layout with AI/companion suggestions. |
| #78 | Children #451-#453 closed complete; 7 drag/drop call sites in IOSDispatchPage; AI Suggest via AIDispatchService on ShortTermPipelinePage:118. |
| #43 | 11 of 12 T3 items verified resolved; convert the last 2 ContentUnavailableView files (IOSTeamsPage, CategoriesTreeView) in batch B15, then close with per-item evidence. |
| #92 (tracker) | All 4 child bugs #426-#429 closed and spot-verified on main (PartsCompanionsPage.swift:843, PartsService.swift:5248/5655); its own triage recommends closing. |
| #88 (tracker) | Beta-scope slices verified on main (IOSReceivingPage Job Return, IOSStagingPage states); floor-plan polish explicitly descoped by owner per #904. |

---

## 3. FIX BATCHES (valid issues, PR-sized, in execution order)

**Ordering: P0 → beta-blocker areas in goal order (parts catalog → parts tracking → JPO → PO → job tracking → time tracking → notebook) → cross-cutting P1/P2 umbrellas → P3 polish.**

### P0 — land first

**Batch A — Input-validation gaps** — #1337 (+#1173) — *PR #1346 already open.* Route inputs through validators, positivity checks, visible validation labels; includes the silent cost-clear data-loss bug in CascadePriceEditSheet. Action = unblock the PR (§5), incorporating the 2 valid Copilot findings (persist trimmed companyName; align industry validation). **Size: PR-completion, medium.**

### Beta-blocker area 1-2: Parts catalog & pricing

**Batch B — Sheet dismiss-ordering (Parts)** — #735, #736. Move `dismiss()` before `await onComplete()` in SmartDeleteSheet (both paths) and PricingBulkEditSheet. Same root cause, one PR. Note: staging branch `fix/sheet-lifecycle-batch` already exists at main tip. **Size: trivial.**

**Batch C — Colors/SKU Phase 3 order-flow wiring** — #242, #243 (closes tracker #98). Re-land the JPO General/Specific brand toggle UI (service already persists brand_selection_mode); wire resolved-brand pill/warning into PO generation + add po_line_items.brand_id migration + persist on generatePOsFromProcurement. **Size: small + medium, one PR or two stacked.**

**Batch D — Supplier & pricing re-lands** — tracker-parents #84 (#440–#442) and #83 (#443). Fix calculateSupplierScores to count `return_to_supplier` (PartsService.swift:7690 vs WarehouseModels.swift:23), add supplier traceability UI, re-land Part-level target in PricingOverrideFlow. Closes both umbrella trackers. **Size: medium.**

**Batch E — Catalog smart-card filters** — #67. Replace PartsCatalogPage filterMenu chips with smart-card stat filters + count badges (the one remaining WEI-446 gap). **Size: medium.**

### Beta-blocker area 2: Parts tracking (scanning + warehouse)

**Batch F — Scanning/QR reliability** — #1208, #1080, #700. Thermal-specific label layout (zero-margin/full-page for exact-media pages) + geometry tests; gate camera behind `isSourceTypeAvailable` with fallback UI; pass entityType/entityId through QR scan navigation routes and consume in parts/warehouse/tools/jobs destinations. **Size: 2 small + 1 medium; one PR (or #700 split).**

**Batch G — Warehouse data integrity** — #1165, #494, #91, #75. Service-layer dimension/placement validation in addStorageUnit; flagForMultiUserAudit guards (already-flagged / no-eligible throws) + inline error in send sheets; persist PartsFlowWizard onboarding counts/locations to canonical stock records instead of notes-field concatenation; add "While You're Here" quick-audit prompt (last open slice of #75). **Size: 3 small + 1 medium; 1–2 PRs.**

### Beta-blocker areas 3-5: JPO / PO / configurable PO

**Batch H — Dead-end controls umbrella** — #1338, #1188, #1206 (+ #1191 chat quick actions, same class). Wire or hide: pairing-code dead end (issueShopPairingCode has no UI caller vs DevicePairingView:219), PO-management bulk actions that only show ComingSoon, "View Public Report" guaranteed-error row, message-thread no-op quick actions. Note: staging branch `fix/1338-dead-end-controls` exists at main tip. **Size: medium umbrella PR.**

*(PO/JPO SQL integrity and error-surfacing are covered by PRs #1344/#1343 — see §5.)*

### Beta-blocker area 6: Job tracking

**Batch I — Job edit template mutation** — #1105. Track explicit picker change in IOSEditJobSheet + add no-workflow option so unrelated edits stop assigning workflows. **Size: small.**

### Beta-blocker area 7: Time tracking

**Batch J — Time-tracking correctness** — #1097 + tracker #90 re-verify. Widen timesheet-correction audit filter to original OR adjusted clock-in (ReportsService.swift:518-525); re-verify children #435–#439 against main and re-land #435's duplicate break/lunch-policy idempotency fix (commit c1f4a335 never merged; testSaveCompanyPolicyIsIdempotent absent). Note: staging branch `fix/time-labor-field-batch` exists. **Size: small + medium.**

### Beta-blocker area 8: Notebooks

**Batch K — Notebook feature re-land** — #80. Re-land slash command palette, panel-circuit drag/drop + classification, PDF export/print/custom header (WEI-1134/1135 commits never merged; PanelScheduleExport.swift missing). **Size: large — split into 2–3 PRs (palette / panel DnD / export).**

### Cross-cutting P1/P2 umbrellas

**Batch L — Silent-error surfacing wave 2** — #1174, #1177, #1178, #1196, #1102, #1101, #724. One umbrella PR per repo rule: replace `try?`-to-empty patterns with loadError + ErrorStateView + retry (notebook templates, subcontractor schedule sheet, message-thread loadData + CreateChannelSheet suppliers, tool detail trades/maintenance); do/catch the attachment temp-write and only append on success (#1101, data-loss class); fail closed when currentUser is nil in AI panel (#724). Staging branch `fix/silent-failures-tracked-batch` exists. Follows the exact convention PR #1343 establishes. **Size: medium umbrella.**

**Batch M — Accessibility pass** — #1184 (umbrella), #1199, #1311. One coordinated pass: accessibility labels on icon-only buttons (verified examples in IOSMainView, IOSPeerBrowser, FirstVisitHint + owner-audit additions), 44pt tap targets (QRLabelPrintSheet minHeight 30→44), dynamic-type/ScrollView fix in OnboardingWalkthroughView + regression test. **Size: medium.**

**Batch N — Q&A/RFI ownership filters** — #1200. Add current-user/role + escalation-level filters to needsMyReview and RFI list queries. **Size: medium.**

### P2/P3 polish (queue after beta-blockers)

**Batch O — Dashboard/onboarding polish** — #1067 (clear isOnboardingActive on finish/skip), #1098 (FAB/toast collision + bottom insets), #1099 (quick-action strip scroll affordance), #708 (badge oldest-pending across all queues), #714 (ToolTradeSheet isDirty on selection). **Size: 5 smalls, one PR.**

**Batch P — Hardening trivia** — #711 (MainActor.run in QRScanSheet), #712 (unused test binding), #1314 (export help copy + stable sheet ID + off-main export), #43 remainder (2 ContentUnavailableView files), #279 follow-up (3 residual Fleet isLoading files). **Size: trivial batch, one PR — then close #43/#279 with evidence.**

**Batch Q — presentationDetents sweep** — #248 + #278. Module-by-module detents rollout (Settings 34/0, Warehouse 25/3, Reports 19/0, Parts 17/1, Orders 15/0, Fleet 13/0) folding in the never-merged Fleet slices (detents, trailer NavigationLink, search empty state). **Size: large — one module per PR.**

**Batch R — Beta bug-report flow** — #574. In-app bug report (Settings entry + assistant + error self-report to GitHub). High tester value — consider promoting before beta launch. **Size: medium.**

**Batch S — Build-warning burn-down** — #1139. **Size: medium, one pass.**

**Batch T — Dev tooling** — #256 (parts-drift-detector subagent). Internal-only; lowest priority. **Size: medium.**

*(#513 branch drain → §7; #79 formal RFI → owner decision §4.)*

---

## 4. OWNER DECISIONS (exact call needed)

1. **#1339 — Repo size:** Choose **Option A** (destructive `git filter-repo` history rewrite, large, must coordinate with #513 drain) vs **Option B** (accept 1.21 GiB clones + partial-clone docs — already shipped in PR #1345's SETUP.md). *Recommendation from audits: Option B now, defer rewrite until post-beta.* Also approve the local-only `git reflog expire --expire=now --all && git gc --prune=now` (reclaims ~6.5 GiB of reflog-only DerivedData blobs; discards reflog undo history).
2. **#851 — Payment Tracking settings:** Hide the coming-soon menu item for beta (trivial) **or** build the page now (medium). *Recommendation: hide for beta; fold into Batch H (dead-end controls).*
3. **#635 — Omi intake umbrella:** Confirm the voice-rant content is fully captured by #645's merged roadmap → close, or enumerate remaining items.
4. **#79 — Formal numbered RFIs:** Implement rfi_objects (unused table, medium effort) **or** descope for beta and close. *Recommendation: descope; informal Q&A/RFI flows are shipped.*
5. **Branch `add-claude-github-actions-1782966374888`:** Install the Claude PR Assistant / Code Review workflows or discard the branch.
6. **Bulk local-branch scratch deletion:** Approve deleting all local branches matching `^(pr-|review-pr-|tmp-review|verify-pr-)` older than 14 days plus the 152 UNKNOWN scratch list (§7) — audit found no PR records for them.

---

## 5. PR ACTIONS (#1343–#1346 — merge in this order)

**Merge gate reminder:** required check = `Analyze (swift)` on an up-to-date head, strict=true, all review threads resolved, Copilot review present. #1343 and #1346 share 5 files — land #1343 before #1346.

1. **#1344 (soft-delete filters → closes #1336) — FIRST, fastest win.** Only blocker: two bot-triggered runs held at action_required. Approve: `gh api -X POST repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runs/28570283238/approve` and `.../runs/28570283220/approve` (or "Approve and run" in UI). Once Analyze (swift) is green on head 43dfd22 → merge (Copilot done, 0 unresolved threads).
2. **#1343 (silent load failures → closes #1335) — SECOND.** Fix the 2 round-3 Copilot findings on IOSPODetailPage.swift (clear stale receiptBatches/entries in catch; clear per-entry "Loading" row when getReceiptHistoryItems throws), resolve both threads, then `gh pr update-branch 1343` **as owner xXKillerNoobYT** (not the bot — avoids the action_required trap), wait for Analyze (swift), merge.
3. **#1345 (docs overhaul → closes #1334) — THIRD.** Content fix required, not just thread resolution: replace every `Wierd Parts.xcworkspace` reference (README.md, docs/SETUP.md ×3, DEPENDENCIES.md, KEY-PRINCIPLES.md ×2) with the tracked `Weird Parts.xcworkspace`; resolve the 5 threads; update branch as owner; merge. Also `rm -rf 'Wierd Parts.xcworkspace'` locally and fix whatever still opens the misspelled path.
4. **#1346 (validation gaps → closes #1337) — LAST.** Merge main into `fix/1337-validation-gaps` resolving the single conflict in IOSScheduleConfigPage.swift (keep BOTH #1324's dirty-tracking and this PR's trims — complementary); fix the 2 valid Copilot findings (persist trimmed companyName in CompanySetupWizard; align industry validation in BusinessProfileSetupView); push as owner. **This branch has never had a CI run** — the push fires pull_request CI for the first time; wait for green, resolve threads, merge.

---

## 6. CI FIXES

1. **Kill the action_required deadlock (root cause, recurs on every train rebase):** create a fine-grained PAT (Contents + Pull requests R/W), `gh secret set PR_MAINTENANCE_PAT`, change `.github/workflows/pr-merge-maintenance.yml` line 43 to `GH_TOKEN: ${{ secrets.PR_MAINTENANCE_PAT || github.token }}`. (Fallback: relax approval policy to `first_time_contributors_new_to_github` — weaker.)
2. **Paperclip Tracker Sync (100% cancelled, 15/15 runs):** repoint secret `gh secret set PAPERCLIP_API_URL --body 'http://localhost:3100'` (runner is on the same Mac); add `--connect-timeout 10 --max-time 120 --retry 2` to both curls at scripts/paperclip-github-tracker-sync.sh:115/119 + a pre-fetch echo; refresh the stale "cloud billing unavailable" comment in the workflow; verify with `gh workflow run 'Paperclip Tracker Sync'` and a fresh sync on issue #372.
3. **Add `workflow_dispatch:` to codeql.yml** so missed weekly full Swift scans (Mon 06-29 dropped) can be re-fired manually.
4. **Disable the ghost "WiredPartCore Smoke" workflow** registration (file absent from main).
5. **Low priority:** bump actions/checkout + actions/cache to Node-24 majors; add `permissions: contents: read` to artifact-guard.yml; consider dropping repo default workflow permissions from write to read.
6. **Hygiene chore PR:** append `=`, `[object Object]/`, `.playwright-mcp/`, `docs/testing/artifacts/` to .gitignore; optionally add path prefixes to the guard's BLOCKED list. Locally: `rm '='`, archive + `rm -rf '[object Object]'`, delete .DS_Store files.

---

## 7. BRANCH CLEANUP (defer execution until PRs #1343–#1346 + fix batches merge)

**Counts:** 857 local (603 merged, 98 obsolete, 152 unknown scratch, 4 active) · 36 remote (4 active PRs, 3 unique-work, ~24 obsolete, 5 investigate) · 23 stale remote-tracking refs from removed remotes · 100+ worktrees (~71 holding merged branches).

Command groups (pre-generated lists in the branch-audit scratchpad; use `git -C /Users/IA/GitHub/Weird-Part-Run-2 ...`, never `cd &&` — the latter hangs on permission prompts):

1. **Local merged phase 1 (532):** delete ancestors-of-main + squash-merged heads via `delete-local-merged.txt` (includes the 8 zero-delta `worktree-agent-a*` placeholders).
2. **Local merged phase 2 (71):** `git worktree remove --force` the merged-work worktrees (esp. ~60 under .paperclip/worktrees), then `branch -D`, then `worktree prune`. **EXCLUDE:** agent worktrees holding the 4 open-PR branches, the 4 batch staging branches (`fix/sheet-lifecycle-batch`, `fix/silent-failures-tracked-batch`, `fix/1338-dead-end-controls`, `fix/time-labor-field-batch`), and the live session worktree.
3. **Stale remote-tracking refs (23):** `git branch -rd github/main pr/{728,743,...,914} pull/{1051,1090}`.
4. **Local obsolete (91):** `xargs -n 30 git branch -D < delete-local-obsolete.txt`.
5. **Remote obsolete (24):** single `git push origin --delete ...` per the audited list (each has supersession evidence). Brings origin 36 → ~12, under the 20 soft cap → **update and close #513** with the audit as evidence.
6. **Keep + PR the unique work:** `WEI-2958` (stage-3 PDF/OCR import adapters) and `WEI-2953` (universal-import plan doc — must land in docs/plans/ per repo rule); investigate `codex/wei-1028-auth-hardening`, `codex/wei-1101-break-policy-presets` (relevant to Batch J!), `WEI-2504`, `wei-1273-generic-supplier-locks` (relevant to Batch D) before deleting.

---

## 8. ITERATION SEQUENCING

### THIS 6-hour iteration (highest leverage, mostly unblocking + closing)

1. **Approve the 2 stuck runs → merge PR #1344** (closes #1336). ~10 min.
2. **CI root-cause fix:** PR_MAINTENANCE_PAT + workflow edit + tracker-sync curl/secret fix + codeql workflow_dispatch (one small CI PR through the normal gate). Prevents the trap from re-stalling steps 3–5.
3. **Fix + merge PR #1343** (closes #1335): 2 Copilot findings, resolve threads, owner update-branch.
4. **Fix + merge PR #1345** (closes #1334): Wierd→Weird content fix, resolve 5 threads, owner update-branch.
5. **Rebase + fix + merge PR #1346** (closes #1337 — the P0): single-file conflict resolution, 2 Copilot findings, first CI run.
6. **Close the 20 CLOSE NOW issues** with evidence comments (§2).
7. **Post the 6 owner-decision questions** (§4) — plain-English, Keep/Adjust options — so answers are ready next iteration.
8. **If time remains:** Batch B (#735/#736 dismiss-ordering, trivial, staging branch exists) through the Copilot gate.

*Realistic completion: 5 issues fixed via PR merges + 20 closed + P0 cleared = 25 of 80 resolved, merge train unjammed, CI self-healing.*

### Iteration +1 (next 6h)
- Batch H (dead-end controls — staging branch ready, fold in #851 hide if owner approves), Batch L (silent-error wave 2 — staging branch ready), Batch I (#1105), Batch J part 1 (#1097).
- Before Batch J/D coding: diff `codex/wei-1101-break-policy-presets` and `wei-1273-generic-supplier-locks` for salvageable work.

### Iteration +2
- Batch C (colors Phase 3 → closes #98), Batch F (scanning), Batch G (warehouse integrity).

### Iteration +3
- Batch D (→ closes #84, #83), Batch J part 2 (#90 re-land → closes #90), Batch M (accessibility), Batch E (#67).

### Iteration +4
- Batch K (notebooks #80, split PRs), Batch N (#1200), Batch O + P (polish/trivia → closes #43, #279 follow-up).

### Iterations +5 and beyond
- Batch Q (detents sweep, module-per-PR), R (#574 — promote earlier if beta launch nears), S (#1139), T (#256); **branch cleanup (§7) executes here**, after the fix batches merge; then #513 close, #1339 Option B closeout comment, local reflog gc (with owner approval).

**Standing rules per iteration:** every PR through the Copilot review gate; one PR at a time on the merge train; update umbrella checklists as sub-findings resolve; end each session on `main`.