---
last_updated: 2026-04-17
updated_by: dev-pipeline-manager (run 19 — initial soul creation)
---

# Pipeline Soul — WiredPart Project Memory

> This file is the persistent memory of the dev-pipeline-manager.
> It survives between runs and accumulates knowledge that no single run could develop alone.
> Written by the pipeline-manager. Read before every run. Updated after every run.
> Do not edit by hand unless correcting a factual error.

---

## Project DNA

> Things that are TRUE about this codebase and won't change. Read these before making any decision.
> Each entry has the date it was confirmed and a confidence level.

**Architecture fundamentals:**

- `[HIGH]` The app is iOS-first SwiftUI + GRDB. Every SQL column reference must match the FINAL schema after ALL migrations have run — not just the CREATE TABLE. Scanner tools often check only CREATE TABLE and produce false positives. Always verify with ALTER TABLE migrations before filing a SQL bug.
- `[HIGH]` The test suite is the ground truth. 1302 tests, all must pass. Zero regressions is non-negotiable. When a test fails it usually reveals a real production bug, not a test bug — investigate thoroughly before touching the test.
- `[HIGH]` Xcode AI handles visual/UI surgery. Core Swift (services, SQL, models, sync) is handled by autonomous agents directly. Never create an Xcode AI prompt for something that can be fixed by reading the file and editing it.
- `[HIGH]` `isTableNotFoundError` wraps exist on almost every service method — fresh-install resilience is a hard requirement. New service methods must always include these guards.
- `[HIGH]` The 13-step lifecycle is the authority. No code ships without a plan and answered Q&A. The owner must approve requirements before anything gets built.
- `[MEDIUM]` LAN sync (ConflictResolver, PeerManager, LanSyncServer) is the heart of the architecture. Bugs here are silent and high-consequence — sync issues won't show up in tests unless explicitly tested. Treat sync code with extra caution.
- `[MEDIUM]` The `try?` pattern on write operations silently loses data. Whenever you see `try? service.createSomething()` in a write path, it's almost certainly a bug waiting to surface. Replace with do-catch + user-facing error.
- `[MEDIUM]` SQLite column names trip up constantly. Known historic mismatches: `receiving_sessions.status` is `'completed'` not `'complete'`, `po_line_items.qty_ordered` not `.quantity`, `v.vehicle_name` not `v.name`. When a test finds a SQL error, check the column name against the migration files directly.
- `[LOW]` The `@State` holding `Timer` anti-pattern appears occasionally — timers held in `@State` won't be invalidated on view disappear. Watch for it in new code.

**Team and process:**

- `[HIGH]` The owner designs, the agents build. High-level direction gets translated into high-detail implementation. Ambiguity goes to Q&A — do not guess.
- `[HIGH]` The Q&A file (`docs/dev-qa.md`) is the only channel for design questions. Anything too ambiguous to implement safely goes there and waits.
- `[MEDIUM]` GitHub Issues are the single source of truth for all unfixed problems. Filing an issue isn't bureaucracy — it's the thing that ensures nothing gets lost between runs.
- `[MEDIUM]` Xcode AI prompts stack up if the user isn't actively running them. PE-044 was ready for weeks before being triggered. Don't generate prompts faster than the user can consume them — quality over quantity.

---

## Watching

> Things noticed but not yet acted on. These are observations, not decisions.
> Each item gets a "maturity date" — the earliest date to consider acting on it.
> Before the maturity date: just observe, add notes. After: decide whether to act or extend.

### WATCH-001 — Colors Phase 1 (#234) Assignment Gap
- **Noticed:** 2026-04-17
- **Pattern:** The Colors & Parts redesign Q&A was fully answered 2026-04-14. The migration SQL is completely specified in the GitHub issue body. Yet 3 days later, no agent has started coding it. This suggests a systemic issue: when Q&A unblocks a core-Swift task, no agent is automatically assigned to pick it up. The Xcode prompt queue is the only explicit dispatch mechanism, and it doesn't cover service-layer work.
- **Maturity date:** 2026-04-20 (3 days)
- **Action if nothing changes:** Write a simple dispatch mechanism — when a core-Swift item advances to Step 5 with no agent tagged, the pipeline-manager should directly attempt the implementation in the same run, OR explicitly log it as "unassigned" and flag it in the daily summary until someone picks it up.
- **Notes:** Still unassigned as of 2026-04-17.

### WATCH-002 — PE Prompt Queue Velocity Mismatch
- **Noticed:** 2026-04-17
- **Pattern:** The PE (Xcode AI prompt) queue grows faster than the user can execute prompts. PE-043 sat as NEXT for weeks. PE-044 was written and verified done — but only because the code was committed directly (commit 7024173), not because Xcode AI was triggered. The system generated PE-043 as the "canonical dismiss template" then moved to PE-045 without PE-043 being explicitly executed. This creates a false impression that the prompt queue is progressing.
- **Maturity date:** 2026-04-24 (one week)
- **Action if nothing changes:** Audit all PE prompts in `xcode-ai/fix-prompts/` — count how many are marked NEXT vs. actually executed. If more than 3 prompts are stuck in NEXT, pause generating new ones and flag to user.
- **Notes:** Currently: PE-045 is NEXT (to be written). Worth watching.

### WATCH-003 — #221 LWW Field-Level Timestamps — No Movement
- **Noticed:** 2026-04-17
- **Pattern:** Issue #221 (LWW field-level timestamp upgrade, ~35 tables) has been in the plan since 2026-04-14. It's a large architectural change with a detailed sub-plan (`docs/plans/sync-field-timestamps-upgrade.md`). No agent has touched it. The concern is that it may be silently stagnating — too large for a single run, too important to leave unstarted, but with no clear ownership.
- **Maturity date:** 2026-05-01 (2 weeks — this one needs more time to evaluate)
- **Action if nothing changes:** Break the implementation into a sequenced Phase 1 (add `_field_timestamps` JSON column to 5 most-synced tables), Phase 2 (update ConflictResolver to consult it), Phase 3 (remaining tables). Assign Phase 1 to next hunt-fix run as a direct implementation.
- **Notes:** Complex — don't rush. But also don't let it stagnate forever.

### WATCH-004 — Systemic Silent Failures (#121/#122/#128)
- **Noticed:** 2026-04-17
- **Pattern:** Three systemic issues have been open for weeks: 198 `try?` instances (#121), 426 silent guard-let bails (#122), 0 truly empty catches across 72 files (#128). These are filed, documented, and un-acted-on. The issue isn't that they're hard to fix — it's that they're each 100+ location changes that feel overwhelming as a single item.
- **Maturity date:** 2026-04-24 (one week)
- **Action if nothing changes:** Instead of treating each as one big ticket, convert them into rolling campaigns: fix 10 instances per hunt-fix run, prioritized by module (Jobs > Sync > Orders > ...). The number decreases steadily instead of staying at 198 forever.
- **Notes:** These are behavioral debt, not crashes. Manageable in small bites.

---

## Deferred Queue

> Things I've decided to handle at a specific future time — not now.
> Format: what, why deferred, when to act, what to do when triggered.

| ID | Item | Deferred Until | Why Waiting | What to Do When Triggered |
|----|------|---------------|-------------|--------------------------|
| DEF-001 | **Implement Colors Phase 1 (#234) migration** | 2026-04-20 | Q&A was just answered — let plan-enforcer and test-coverage confirm the design before touching the schema. Three days gives time for any follow-up questions to surface. | Read `docs/plans/colors-parts-redesign.md` and GitHub issue #234, then implement the migration in `AppDatabase+Migrations.swift` and update `PartsModels.swift`. Write 3 migration tests. |
| DEF-002 | **Begin #221 LWW field-level Phase 1** | 2026-05-01 | This is a ~35 table schema change. Let it sit until the Colors Phase 1-3 work is underway — don't start another major schema campaign while one is in flight. | Read `docs/plans/sync-field-timestamps-upgrade.md`. Add `_field_timestamps` TEXT column to the 5 tables that sync most frequently (parts, jobs, stock_movements, orders, employees). Update ConflictResolver to read it. |
| DEF-003 | **Silent failures rolling campaign (#121)** | 2026-04-25 | Let the current working tree get committed and the working tree stabilize first. Don't layer more changes on an uncommitted tree. | Pick the 10 highest-traffic `try?` instances (from scan of Jobs, Sync, Orders). Convert to do-catch with `logger.warning()`. Commit. Repeat next week. |
| DEF-004 | **Audit PE prompt queue velocity** | 2026-04-24 | Too early to tell if this is a real pattern or a one-off. Give it a week. | Count PE prompts in `xcode-ai/fix-prompts/` vs. archived in `done/`. If NEXT queue > 3, pause generation and flag to user with a clear "these prompts are waiting to be run" message. |

---

## Hard-Won Knowledge

> Things that went wrong or were subtly wrong — lessons that must not be lost.
> These inform HOW to do work, not just WHAT to do.

**SQL:**
- `receiving_sessions.status = 'complete'` is WRONG. The correct value is `'completed'`. Was in 2 SQL queries for months. Discovered only because a test tried to join on it.
- `po_line_items.qty_ordered` not `.quantity`. Column names don't always match what sounds intuitive. Always check the migration file before writing a new query.
- `v.vehicle_name` not `v.name` in the vehicles table. Same lesson.
- SQL scanners that only read CREATE TABLE always produce false positives on columns added via ALTER TABLE later. Never file a SQL bug based on scanner output alone — verify against the full migration history.
- `GROUP BY` is required when `HAVING` is used. SQLite is unusually permissive here but GRDB's strict mode catches it.
- SQL argument count must exactly match `?` placeholder count. `HAVING total_stock > 0` with 1 argument when no `?` exists = crash. `PartsService.checkInventoryForDeletion` had this.

**Tests:**
- The `AuthService.loginAttempts` static dict is shared across all parallel test runners. Any test that touches lockout state must either use `.serialized` on the test suite or reset the static before each test. Learned the hard way when `.serialized` had to be added to `AuthServiceTests`.
- Tests that find SQL errors are usually catching real production bugs — `PartsService.findOverrideConflicts` and `listLocationStockTargets` had SQL column name errors discovered only via test coverage expansion.

**Architecture:**
- `try?` on write operations silently loses data. This has been fixed in 12+ locations. Every new service method should use do-catch.
- `currentUser?.id ?? 1` in write paths is an anti-pattern. The `1` means admin in most contexts, silently attributing all writes to the admin user. Fixed in 7 locations (DIS-016). Watch for it in new code.
- Companion vote power permissions must be seeded in `AuthService.defaultPermissionMap()`. If a new permission key is added to the app but not to this map, it's silently invisible to all users.

**Process:**
- Retroactively closing GitHub issues without verifying the fix was actually committed is a real problem. The `issue-closure-verifier` was created specifically because issues were being closed prematurely. Never close an issue in a comment unless you've verified the commit SHA that contains the fix.
- When two agents run in parallel on the same file, one will get a "file modified since read" error. This is normal. Re-read and retry.

---

## Instincts

> Patterns I've noticed about how this project works. Softer than DNA — more like intuition.
> These are hypotheses, not facts. They should influence decisions but can be overridden.

- **The schema is the bottleneck.** When a feature stalls, it's usually because a schema change is needed and nobody has defined it clearly enough. The Colors redesign stalled for 3 days after Q&A because the migration SQL wasn't spelled out explicitly enough in the dispatch. Now that #234 has the full SQL in the issue body, it can move forward.
- **Security bugs get fixed fast when named clearly.** #191 (unauthenticated key exchange), #184 (JSON injection), #230 (silent plaintext fallback) — all three were fixed within days of being filed because the fix was precise. Vague security findings stagnate. Specific ones don't.
- **Large systemic fixes need to be chunked.** The #121 (198 `try?`) campaign has been open for weeks with no progress. The formatter sweep (#146) was 99 inline instances — it got done because it was split into batches. Rolling campaigns with a fixed "10 per run" quota are more effective than one giant ticket.
- **The owner doesn't want to be bothered with things agents can handle.** Q&A goes to the owner only for genuine design decisions (what should this do? how should this work?). Technical questions (how do we implement it?) are for agents to answer themselves.
- **The Xcode AI prompt queue is only as fast as the user is.** Agents should not pile up more than 3 unrun PE prompts. If they're stacking up, something is wrong with the trigger cadence.
- **Test coverage runs find real bugs.** Every time the test-coverage-maintenance agent writes a new test, it finds 1-2 production SQL bugs. This is a feature, not a coincidence. The test-writing process forces the agent to run the actual code paths.

---

## Mood

> A qualitative read on the health of the project. Updated each run.
> Scale: 🔴 Struggling → 🟡 Tense → 🟢 Healthy → ✨ Thriving

**Current: 🟢 Healthy — leaning toward ✨**

The project is in genuinely good shape. 1302 tests all passing, build clean, Q&A at zero (first time), no critical security bugs open. The working tree is overdue for a commit but the changes are all plan-aligned. The main risk is that the deferred queue has accumulated some items that need careful handling (Colors Phase 1, LWW upgrade) — if these sit unattended another two weeks the window of easy implementation will close.

**Last mood check:** 2026-04-17

---

## Conversation Log

> Brief entries from each run — what was the main thing the pipeline-manager noticed or decided.
> Newest first. Keep last 20 entries.

- **2026-04-17 (run 19):** Soul file created. Initial DNA written from project history. 4 items added to Watching, 4 items added to Deferred Queue. Q&A backlog at 0 for first time. Colors Phase 1 dispatched. Working tree 11 files overdue. Next Up section cleaned up (removed duplicate items, stale Q&A counts). Key insight: pipeline needs a deferred dispatch mechanism — core-Swift tasks unblock but then drift unassigned.
