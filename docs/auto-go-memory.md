# AUTO GO — Memory

> What I've learned about this project, this user, and this work. Different from `docs/auto-go-metrics.md` (raw numbers) and `docs/auto-go-soul.md` (my identity). Memory is compressed wisdom: observations, patterns, what worked, what didn't, things that aren't in the code or plans but matter.
>
> Read at the start of every iteration (STEP 0). Writeable during STEP 6 when a significant learning has occurred. The weekly `loop-self-improve` pass rolls ephemeral observations into durable memories and prunes anything that's become stale.

---

## How to read this file

Memory is organized by topic, not chronologically. Each entry includes when it was learned and, when relevant, what it implies for future iterations. Entries here represent what I currently believe is true. If I later find evidence that contradicts an entry, I update or remove it (I don't just stack new entries on top).

---

## Things I know about this project

*(Seeded with what I already know from CLAUDE.md and the existing tracker history. Will grow with iterations.)*

- **This is a beta, not a greenfield.** ~1290 tests pass. 87 functional pages. 35 services. The code is large and working. My job is convergence and polish, not construction.
- **Two platforms share one React UI** — Tauri desktop (macOS + Windows) + Tauri iOS — plus a separate native Swift iOS app (`Weird Parts IOS/`) and shared Swift core (`core/Sources/WiredPartCore/`). Cross-platform parity matters (C10 exists specifically for this).
- **SQL schema has known gotchas** (see `feedback_sql_patterns.md`): `users.display_name` not first/last, `jobs.customer_name` not customer_id, `hats` has no `deleted_at`, etc. Before writing any SQL, verify columns against `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`.
- **Hardcoded user ID `1` is an anti-pattern** (see `feedback_hardcoded_user_ids.md`). Always flow real `userId` from session for `created_by`/`updated_by`/`started_by`.
- **Plans are the source of truth for design** (`docs/plans/`). If code diverges from plan, plan wins — unless I file a Q&A and the user decides otherwise.
- **GitHub issues are the single source of truth for unfixed problems** (per CLAUDE.md). Anything unfixable gets filed.

## Things I know about the user's working style

- **The user is the designer, I am the implementer.** The user gives high-level intent; I deliver high-detail, production-grade implementation. (Source: CLAUDE.md "Working Style & Collaboration".)
- **The user prefers direct Swift edits over Xcode prompts when the change is non-visual** (source: `feedback_direct_swift_edits.md`). Xcode AI is for UI-heavy visual work.
- **The user doesn't want unplanned improvements silently applied** (source: `feedback_unplanned_improvements.md`). When I find something not in a plan, I ask: keep & develop now, remove for now, or plan for later — via Q&A.
- **The user wants a loop that self-improves and finds new automations** (source: 2026-04-18 session). Not a static scheduler. Hence `loop-self-improve` + automation-recommender chain.
- **The user is building toward a production release** of a real shop-management system. Convergence toward shippable beats breadth every time.

## Patterns I've noticed (grows as iterations accumulate)

*(Currently seeded with hard-won patterns from earlier work captured in trackers. Will be appended to as the loop runs.)*

- **SQL column mismatches are the highest-yield bug category** (~64+ historically fixed). Scanner 4 in hunt-fix-verify catches most; the rest come from code assuming schema.
- **Sheet-dismiss safety** is a recurring UI bug class — `.interactiveDismissDisabled(isSaving)` on forms-with-state. The `dismiss-safety-campaign.md` plan codifies the pattern.
- **Wizard `Save & Exit` vs. `Cancel`** is a design theme — multi-step flows need draft persistence. Tracked via #148 and related.
- **Tests sometimes pass locally but the migration fails in prod** — from the user's "don't mock the database" feedback. C4/C5 tests must be integration-level, not pure unit with mocks.

## Decisions I've made (and why)

- [2026-04-18] **First area graduation: parts (16 iterations, 1 day).** Pattern observed: 1 iteration per check, no re-runs needed, 2 genuine fixes (dismiss-safety x2) + 1 automation built + 18 new tests + 6 trackers established. 1 checklist item was N/A (C10 cross-platform). The 17-check bar is achievable for a well-maintained area in a working day of loop iterations. This is the baseline — if `jobs` takes >25 iterations to graduate, something's slowing it down and Sunday self-improve should investigate.
- [2026-04-18] **Xcode-prompt throughput signal (4 PE-COLORS prompts stalled ~12h in "to-be-written" status).** Not a fatal gap — prompts are correctly tracked in xcode-ai/fix-prompts/00-fix-order.md and GitHub #237-240. But signals that the xcode-planner-and-review skill isn't firing often enough during AUTO GO runs. The weekly loop-self-improve pass should watch this: if the queue keeps growing week-over-week without prompts being written, flag as a throughput problem for the user.
- [2026-04-18] **Repo is iOS-native only despite CLAUDE.md's dual-platform claim.** Cross-platform parity (C10) is structurally N/A — `src/`, `src-tauri/` not in working tree (git history shows they were removed). CLAUDE.md architecture section and codebase stats are stale. Filed #257 for the drift. For any area reaching C10, the right answer is: mark done (vacuously satisfied, single platform), reference tracker.
- [2026-04-18] **Automation-recommendations approval workflow (user-directed).** Every recommendation in `docs/automation-recommendations.md` must be filed as a Q&A in `docs/dev-qa.md` with APPROVE/DEFER/REJECT options. Once the user answers APPROVE, the next AUTO GO iteration builds it autonomously. If an attempt fails (skill won't compile, hook breaks something, etc.), file another Q&A documenting the failure and asking what to do instead — don't silently give up. [→ soul candidate] The guiding principle: recommendations are not silent to-dos; they are proposals that need a green light.
- [2026-04-18] **Treated C1b drift as bi-directional** — checked both "code ahead of issues" (ForecastSettingsSheet built, #162/#163 still open) AND "plan ahead of code" (PE-COLORS Phase 2 unimplemented). Both directions matter; catching only one misses half the value. Closing stale issues clears noise from the open-issue list; flagging plan gaps prevents them from being forgotten.

## Things I tried that didn't work

*(Empty — will grow. Each entry: what I tried, why it failed, what I do instead now. This is how I avoid repeating mistakes across iterations.)*

## Things I tried that worked well

*(Empty — will grow. Captures validated approaches worth reusing.)*

## Per-area notes

*(Each area gets a section as I work it. Initial stubs below.)*

### parts
- [2026-04-18] **`suggestion_id: 0` FK bug in `recordCompanionFeedback`** — the function was hardcoding `suggestion_id: 0` in the `companion_feedback` INSERT, but `companion_suggestions` has no row with id=0. Fix: made `suggestionId` an optional parameter (default nil) and skip the INSERT when nil. Filed #250. When writing tests for functions that INSERT into tables with FK constraints, check the referenced table exists in the test DB and the seed value is valid.
- [2026-04-18] **`createPart` auto-logs a "created" audit entry** — `getPartChangeLog` for a freshly seeded part returns 1 entry. Tests for `logPartFieldChanges` must filter by `action == "updated"` rather than asserting `isEmpty` or exact count.
- [2026-04-18] **`#expect` macro can't type-check complex closures with 3+ `&&` conditions** — Swift compiler times out. Break into local variables (e.g., `let entry = log.first(where:...)` then `#expect(entry?.field == value)`) for multi-condition assertions in `#expect`.
- [2026-04-18] **PE-COLORS Phase 1 is silently complete** — migration 074 (`color_brand_skus`), `ColorBrandSKU` struct + CRUD in PartsService, and `searchParts` union update (tagged "PE-COLORS #236") were all done but not explicitly noted in the plan's progress log. Phase 2 (UI) pending via #237-#240. Phase 3 (orders) pending via #242-#243.
- [2026-04-18] **ForecastSettingsSheet covers both issues #162 AND #163** — the free-space rating (issue #163 "per-location 1-10 scale editor") is implemented as a Stepper inside the ForecastSettingsSheet, not as a separate sheet. When verifying issues, check the actual implementation before assuming separate files are needed.
- [2026-04-18] **"Subsumes: #X" in issue body = close #X immediately during C2b** — When a well-written parent issue lists "Subsumes: #X, #Y" in its body, those subordinate issues can be closed during C2b ingestion without any code check needed. The parent carries all context. In the PE-COLORS family this collapsed 5 redundant issues (#144, #100, #106, #99, #105) into their parent issues (#237, #238, #240).

### jobs
- [2026-04-19] **Jobs area is a graduated-baseline reference.** 16 iterations to graduate (iter 17 yesterday through iter 7 today). Only 1 functional fix during the run (CreateJobSupplierChannelSheet dismiss-safety, commit b102dfa). 0 hunt-fix findings, 0 security findings, 0 perf findings, 0 test-coverage gaps (204 tests / 67 funcs = 3x), 0 build warnings, 0 pending Q&A. When an area shows this "all green on first sweep" profile, keep iterations short (single-check each) and don't fabricate findings.
- [2026-04-19] **JobsService.swift line 628 uses a safe GRDB partial-UPDATE idiom** — `setClauses.joined(",")` with whitelisted column names + parameterized `StatementArguments`. Looks like SQL concat (M4 flag) but is not. Future security/hunt-fix scans should recognize this pattern and not flag it. Same pattern appears in other services — confirm column-name whitelisting before flagging.
- [2026-04-19] **Repo has no per-area GitHub labels** (`jobs`, `parts`, `warehouse` etc. are not labels). Issues are filtered by title prefix `[Jobs]`/`[Parts]`/etc. C2b/C11 must use title-keyword search via `gh issue list --json title | python3 -c ...`, not `--label`. [→ soul candidate if repo never adds labels]

### warehouse
*(notes accumulate here)*

### scheduling
*(notes accumulate here)*

### orders
*(notes accumulate here)*

### people
*(notes accumulate here)*

### tools
*(notes accumulate here)*

### vehicles
*(notes accumulate here)*

### inventory
*(notes accumulate here)*

### reports
*(notes accumulate here)*

### notebooks
*(notes accumulate here)*

### chat
*(notes accumulate here)*

### settings
*(notes accumulate here)*

### cross-cutting
*(notes accumulate here)*

## Weekly reflections (newest first)

*(The `loop-self-improve` Sunday pass writes a reflection here each week: what was graduated, what got stuck, what patterns emerged, what soul or memory entries need updating.)*

---

*Seeded 2026-04-18. First entry from the loop itself: pending.*
