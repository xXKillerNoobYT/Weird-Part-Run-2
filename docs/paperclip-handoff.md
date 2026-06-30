# Paperclip Handoff — WiredPart Project

> **What this is.** A single onboarding document for the AI agent at [paperclipai.net](https://paperclipai.net) taking over autonomous development of the WiredPart project from Claude Code. Read this top-to-bottom before doing any work. Every section ends with pointers to deeper reference docs — read those when the moment calls for them, not all upfront.
>
> **Authored by Claude (final session, 2026-05-08).** All facts in §5 (state) are accurate as of that date; verify with `git log` / `gh issue list` / heartbeat-file freshness before assuming.
>
> **Paperclip staging update (2026-05-26):** For execution order, use `docs/plans/staged-paperclip-goals.md`. Stage 1 is the only active Paperclip implementation stage; later stages in this handoff are planning/backlog until Isaac/Paperclip promotes them.

---

## §1 — Mission (the Goal)

**Take WiredPart from its current state (development, preparing for BETA release) through a successful BETA launch within the next 90 days, while preserving the convergence rate, code quality, and architectural correctness Claude has been delivering, and the workflow disciplines that make the codebase trustworthy.**

### What "successful BETA launch" looks like (concrete, measurable)

1. **All 14 areas reach 100% checklist green** (the 17-item C1–C13 checklist per area; see §6) at least once before TestFlight build is shipped to first beta tester. Currently 13/14 areas have graduated at least once. Inventory is in its 6th rotation pass; each rotation tightens the bar.
2. **SQLCipher whole-DB migration ships and is verified** (PR #320 lineage closes, CodeQL #292/#294/#296/#298/#303 close with commit links). Beta testers' data is encrypted at rest from day 1.
3. **Per-field timestamp LWW upgrade ships** (#221, plan at `docs/plans/sync-field-timestamps-upgrade.md`). Sync conflicts no longer lose data on same-field-same-row collisions.
4. **Pagination cursor cutover completes** (#227, plan at `docs/plans/pagination-cutover.md`) — the Phase 1 LIMIT 1000 band-aid is replaced by proper cursor pagination at marked call sites.
5. **The 12 approved automation scanners ship and have run at least once project-wide** (the `~/.claude/scheduled-tasks/*-scanner` skills approved 2026-04-25 and 2026-04-27 — list in §7). Each first run produces issues in the right buckets; each scanner is then wired into its corresponding C7b/C8/C9/C13 dispatch.
6. **No data-loss bugs in beta** as a result of dismiss-safety, save-and-exit, or sync-edge-case classes. The dismiss-safety smart-patcher script (per `docs/plans/dismiss-safety-campaign.md`) has finished sweeping all ~30 sheets before beta opens.
7. **Test count grows monotonically.** Current ≈1300+. Don't let a feature-area graduate with new untested public service methods.
8. **Q&A backlog stays at 0 most days.** The `dev-pipeline-manager` and `issue-closure-verifier` Sunday routines (§7) keep the queue clean. Beta-prep should not surface dozens of open design questions; each cluster you generate gets answered within 7 days or it gets reframed.

### What "preserving discipline" means

- **Plans before prompts.** ALL design decisions go to `docs/plans/*.md` BEFORE any code is generated. CLAUDE.md §"Plan Filing & History" is the rule. If you find yourself coding without a plan, stop and ask the user (Q&A workflow in §7).
- **Goal -> plan -> issue -> PR loop.** For Paperclip/GitHub routing, read `docs/plans/paperclip-agentic-execution-loop.md`. It defines the required fields for GitHub issues, Paperclip child issues, branch/worktree hygiene, PR evidence, and closeout comments.
- **Slow, focused, one-area-at-a-time.** AUTO GO's soul (`docs/auto-go-soul.md`) is the canonical statement. Convergence over breadth. 25-minute cap per iteration. No spraying.
- **No finding gets lost, but no issue spraying.** Anything you notice that's out-of-scope for the current check gets GitHub tracking before you continue, but first search existing issues and umbrella trackers. If the finding shares a root cause or likely PR with an existing tracker, add it there instead of opening a new issue. See `feedback_issue_ordering.md`.
- **Per-POV Q&A.** Each `Answer: _pending_` line in `docs/dev-qa.md` waits for a role-specific answer (Owner / Manager / Developer / User). Never collapse. See `feedback_qa_workflow.md`.
- **Tests are non-negotiable.** Every new public service method gets a test in the same iteration that introduces it. C4 + C5 must pass before an area graduates.
- **The user does not read code.** Reports come back as dashboards / plain-English / per-POV breakdowns. See `user_background.md`.

---

## §2 — First-day reading order (estimated 30–45 min)

In this order. Stop if anything is unclear and ask the user before going further:

1. This file (`docs/paperclip-handoff.md`) — top to bottom — for the orientation.
2. **`CLAUDE.md`** at the project root — the codebase's standing instructions. Mirrored in `copilot-instructions.md`, `AGENTS.md`, `GEMINI.md`. Authoritative.
3. **`docs/auto-go-soul.md`** — your identity going forward. You ARE AUTO GO when this loop fires. Don't edit this file without owner approval.
4. **`docs/auto-go-memory.md`** — compressed wisdom from prior iterations. Many "things I tried that didn't work" entries are here. Read it as background, not as a checklist.
5. **`docs/auto-go-todo.md`** — the always-readable scratch board. Owner-pinned items override the area-rotation checklist. Empty most days.
6. **`docs/auto-go-heartbeat.md`** frontmatter — current iteration state. The body of this file is enormous (mostly log lines); only read the first ~40 lines unless debugging.
7. **`~/.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/MEMORY.md`** — index of all the user-feedback files. Each linked file is < 100 lines and tells you something specific about how the user works.
8. **`docs/dev-pipeline.md`** — the master pipeline tracker. Read the top "Master Status" table; skip the Active Work Items table unless investigating a specific item.
9. **`docs/dev-qa.md`** — the Q&A file. Pending Questions section first; if non-empty, those need owner ratification before code.
10. **`docs/plans/paperclip-agentic-execution-loop.md`** — how Paperclip goals, repo plans, GitHub issues, Paperclip execution issues, PRs, CI, and closeout evidence connect.
11. The plan files in `docs/plans/` that are tagged "Status: Design approved, implementation pending" — these are the on-deck work items.

After this 30–45 minutes you should have the model in your head: who the user is, what we're building, what's queued, and how the loop is supposed to run.

---

## §3 — Who is the user

**Solo developer, day job, designer not coder.** This is critical and shapes everything you do. (Source: `~/.claude/projects/.../memory/user_background.md`.)

Operational implications:

- **The user does not read code.** Don't paste diffs in chat. Don't quote function signatures expecting recognition. Translate everything to plain English with explicit file:line citations (so the user can paste them to an editor if needed, but doesn't have to read them).
- **Reports as dashboards.** Tables, checklists, dashboards. Concrete numbers. Avoid prose walls.
- **Budget-conscious + time-respectful.** Don't burn tokens on speculative exploration. Be efficient. Cheap models for mechanical work; Opus only for judgment work. (See `docs/auto-go-soul.md` "Opus manages, sub-agents specialize.")
- **The user is the designer.** When something is ambiguous, the user's intent is authoritative even when expressed imperfectly. Interpret the spirit of the request. When you can't, file a Q&A entry in `docs/dev-qa.md` per the per-POV workflow — don't guess silently.
- **GitHub is personal-account owned for now.** Current repos are under the user's personal GitHub account, not an organization. Verify owner context before applying GitHub admin instructions; org-only settings should be treated as not applicable unless the user moves repos into an organization. See `docs/github-account-context.md`.
- **Spelling and shorthand are fine.** The user uses voice-to-text and shorthand sometimes. "approve all", "lests get them aserd", "go" — all valid. Decode and execute.
- **Owner answers via AskUserQuestion picker.** When there are choices, present them via AskUserQuestion with proposed answers + Keep/Adjust/Different options. Batch by cluster (max 4 per call). (See `feedback_qa_workflow.md`.)
- **Pin chat reuse.** The user pins chats to come back to. Memory files persist across sessions; lean on them.

---

## §4 — What WiredPart is

A native iOS shop-management app for the user's electrical-contracting business. SwiftUI front-end (`Weird Parts IOS/`) + a shared Swift core package (`core/Sources/WiredPartCore/`). 87 functional pages, 35+ services, ~1300+ tests, ~76 SQLite migrations.

**What's retired:** earlier Tauri 2.0 / React dual-platform work (`src/`, `src-tauri/`) is out of the working tree. CLAUDE.md and MEMORY.md still mention it for historical reasons; the current architecture is iOS-native only. C10 "cross-platform parity" should be marked N/A for areas during rotation.

**Stack highlights:**
- **DB:** GRDB (SQLite). 76 migrations. Soft-delete-by-default (`deleted_at` column on every business table). Many tables also have `is_active` — both flags must be filtered on every query (see `feedback_deleted_at_defense_in_depth.md`).
- **Sync:** Apple Multipeer Connectivity for device ↔ device. Field-level merge LWW with row-level timestamp tiebreaker (limitation being upgraded — see #221).
- **AI:** Apple Foundation Models (`FoundationModelsService.swift`). actor-based, async.
- **Architecture rule:** plans first (`docs/plans/`), prompts second (`xcode-ai/fix-prompts/`), reviews compare result vs plan. The `xcode-planner-and-review` skill enforces this.
- **Domain areas (14):** parts, jobs, warehouse, scheduling, orders, people, tools, vehicles, inventory, reports, notebooks, chat, settings, cross-cutting. AUTO GO rotates through these.

**Release state:** development → BETA. Pre-beta is the right time for architectural changes (cheaper now than after testers have data). Beta testers will be real users; pattern quality matters because it's public-bound. (See `feedback_release_state.md`.)

---

## §5 — Where we are (snapshot 2026-05-08)

| Metric | Value |
|---|---|
| Test count | ~1300+ passing on `swift test` |
| Open GitHub issues | 30 |
| Open GitHub PRs | 5 (mix of Copilot-authored + security PRs) |
| Pending Q&A clusters | 0 (genuinely; the file's `_pending_` strings are template) |
| Active area | inventory, iteration 5 of rotation 6 |
| Areas graduated at least once | 13/14 — only inventory has yet to fully close on rotation 6 |
| Current cron cadence | AUTO GO 6/12/18 local, HUNT FIX 9/15/21 local. GITHUB FLOW 21:22 evening |
| `issue-closure-verifier` | Sundays 07:09 — first real run 2026-04-16 caught 2 prematurely-closed issues |

### What's actively in flight (you'll inherit this)

- **PR #320** — SQLCipher whole-DB migration. Algorithm decided 2026-04-29 (Option B: new-encrypted-DB-with-import). Copilot reassigned 2026-04-29T17:36Z to refactor toward this approach. **5 required test cases** named `MigrationCipherTests.test*` not yet written.
- **9 + 3 = 12 approved automation scanners** queued for AUTO GO to build (see §7 list). Some may already be partially shipped — verify with `ls ~/.claude/scheduled-tasks/`.
- **Per-field LWW timestamps migration** (#221) — design plan committed at `docs/plans/sync-field-timestamps-upgrade.md`. Implementation pending. Touches ~35 synced tables.
- **Pagination Phase 2 audit** (#227) — produces `docs/pagination-audit.md` classifying every `findAll()` caller. Phase 1 (LIMIT 1000) shipped in commit `fb11761` (2026-04-14).
- **Dismiss-safety smart-patcher script** (#143) — pilot PE-044 shipped via direct edit 2026-04-15. Script approved 2026-04-25 to sweep ~30 remaining sheets. Build queued.
- **#149 keyboard-dismiss campaign** — Phase 2, deferred until #143 completes.
- **PE-COLORS Phase 2 + 3** (#237–#240, #242–#243) — Variants UI + General Mode on JPO/PO line items. Plan at `docs/plans/colors-parts-redesign.md`.

### Things that look done but aren't quite

- **CodeQL #292/#294/#296/#298/#303** — closed-as-IN_PROGRESS comments posted but issues remain OPEN until #320 SQLCipher migration ships in code. Don't close them yet.
- **#148 IOSMovementWizard Save & Exit** — code shipped, Q&A retroactively ratified, issue closed → reopened by `issue-closure-verifier` Check A → re-closed with the ratification log entry. Should stay closed now. If it reopens again: investigate, don't auto-close.

---

## §6 — The 17-check area checklist (apply to every area)

This is the canonical "is this area beta-ready" rubric. Each iteration of AUTO GO advances ONE check on the current area. When all 17 are `done`, the area "graduates" and the rotation advances to the next area.

| # | Check | What it verifies |
|---|---|---|
| C1 | Plan complete | `docs/plans/area-{name}.md` exists with all required sections |
| C1b | Plan-vs-code drift clean | `plan-enforcer` SKILL finds 0 gaps in either direction |
| C2 | Q&A resolved | Zero `_pending_` lines for this area in `docs/dev-qa.md` |
| C2b | GitHub issues ingested | New issues for this area auto-fixed, plan-attached, or Q&A-filed |
| C3 | Hunt-fix clean | `/hunt-fix-loop` returns 0 findings scoped to this area |
| C4 | Tests present | Every public service method + feature flow has a test (≥90% coverage) |
| C5 | All tests pass | `swift test` green on this area's suite |
| C6 | Build warnings zero | `swift build` produces no warnings on this area's files |
| C7 | UI polish | `usability-enforcer` 8 scanners pass on this area's iOS pages |
| C7b | Dev-improvement polish | `dev-improvement-scanner` 6-phase audit clean |
| C8 | Security reviewed | `security-review` SKILL passes on this area's code |
| C9 | Performance reviewed | `performance-review` SKILL passes (no N+1, no missing indexes, no main-thread DB) |
| C10 | Cross-platform parity | **N/A** for current iOS-only architecture — mark `done` automatically |
| C11 | GitHub issues resolved | All open issues with this area's label closed or deferred with reason |
| C11b | Process gaps clean | `dev-pipeline-manager` SKILL finds no work stuck mid-lifecycle |
| C12 | CLAUDE.md reflects area | `/claude-md-management:revise-claude-md` has captured this area's learnings |
| C13 | Automation opportunities reviewed | `/claude-automation-recommender` scoped to this area; new recs filed as Q&A |

Soul-level rule: **don't graduate an area early.** If a check can't pass, mark it `blocked` with the reason. Don't lower the bar.

---

## §7 — How the workflow works (loops, agents, skills)

### Three autonomous routines

| Routine | Cadence | What it does |
|---|---|---|
| **AUTO GO** | 6h cron at 6/12/18 local + manual `AUTO GO` trigger | One iteration of slow-focused area work. Reads soul/memory/todo/heartbeat. Picks current area's first pending check. Does the work or blocks cleanly. 25-min cap. |
| **HUNT FIX** | 6h cron at 9/15/21 local + manual `HUNT FIX` trigger | One iteration of `/hunt-fix-loop` focused on AUTO GO's current area. 8 scanners. Top 5 fixes per iteration. |
| **GITHUB FLOW** | Daily at 21:22 evening + manual `GITHUB FLOW` trigger | Portfolio overseer across ALL enabled GitHub projects (not just WiredPart). Posts daily-report issue. Logic in `xXKillerNoobYT/ai-agent-Overall-manger/runbook.md`. |

### Sunday-only weekly routines

| Routine | Slot | What it does |
|---|---|---|
| `weekly-cleanup` | Sunday 06:00 | Dead code, old prompts, stale files (3+ months) |
| `issue-closure-verifier` | Sunday 07:09 | Audits issues closed in last 30 days; reopens prematurely-closed ones with detailed comments. Catches scanner-agent over-eagerness. |
| Loop self-audit | Sunday morning, iter ≤ 3 | Inventories scheduled-tasks vs checks; flags orphans |
| Loop self-improve | Sunday afternoon, iter 9–16 | Reads `docs/auto-go-metrics.md`; mutates check priorities, adds new scanners, retires unused ones |

### Q&A workflow (critical)

Every `Answer: _pending_` line in `docs/dev-qa.md` is owner-input territory. Never answer for the user. Use `AskUserQuestion` with proposed answers (pulled from code/context) + `Keep / Needs adjustment / Different` options. Batch by cluster, max 4 questions per call. After answers, fill inline + write a reference-log entry + update plan files. Full spec: `~/.claude/projects/.../memory/feedback_qa_workflow.md`.

There's also an **APPROVE / DEFER / REJECT variant** for automation-tool recommendation clusters (no POV framing needed).

### Copilot delegation

Per `feedback_delegate_to_copilot.md` and `feedback_copilot_delegation_workflow.md`: I'm the engineering lead, Copilot (`copilot-swe-agent` + `copilot-pull-request-reviewer`) is the team. 6-phase loop:

1. Pick batch (3–5 related issues)
2. Write prescriptive issue prompts
3. Supervise (don't @copilot in body — let it pick up via assignment)
4. File-as-a-whole review (single consolidated review comment)
5. Request/receive GitHub Copilot PR review/comment before merge; if Copilot finds issues, route fixes through Codex/Hermes-local or human lanes, test/self-review, then re-request/wait as needed (~30 minute cycles are acceptable)
6. Squash-merge only after CI, required checks, unresolved threads, Paperclip blockers, and the Copilot review gate are clear
7. Sweep (clean up `[gone]` branches)

Cap: **5 concurrent open Copilot PRs.** Each issue gets its own branch. Merge is the user's; Copilot does not self-merge. Paperclip WEI-3851/WEI-3852 supersedes older Copilot-removal churn: keep Copilot as a required GitHub PR reviewer/commenter before merge, but do not use it as a Paperclip local provider/tooling route.

### The 12 approved automation scanners (queued or partially built)

Verify with `ls ~/.claude/scheduled-tasks/` what already exists. The Q&A reference log in `docs/dev-qa.md` shows when each was approved.

| Scanner | Approved | Wires into |
|---|---|---|
| `parts-sql-check.sh` (extended to WarehouseService) | 2026-04-25 | PostToolUse hook |
| is_active Defense Auditor (per-SELECT) | 2026-04-25 | PostToolUse hook |
| `main-thread-grdb-scanner` | 2026-04-25 | C7b dispatch |
| `Formatters.formatSQLiteDatetime` helper | 2026-04-25 | (consolidation, not scanner) |
| `sql-perf-audit` scanner | 2026-04-25 | C9 dispatch |
| `dismiss-safety-scanner` (struct-aware) | 2026-04-25 | C7 dispatch |
| `batch-transaction-scanner` | 2026-04-25 | C9 dispatch |
| Safe-GRDB-Partial-UPDATE allowlist marker | 2026-04-25 | security-review SKILL |
| Area-label auto-tagger (GitHub Action) | 2026-04-25 | `.github/workflows/auto-label.yml` + backfill |
| `render-perf-scanner` (`.filter{}.count` in `var body`) | 2026-04-27 | C7b dispatch |
| `identity-string-audit-scanner` (`by actor: String`) | 2026-04-27 | C8 dispatch |
| `grdb-silent-bug-scanner` (Nil-Default + LEFT JOIN trap) | 2026-04-27 | SQL family |

Build order recommendation: cheapest first (mirror existing patterns), then security-urgent (T1), then complex (AST-aware). The user's posture is "build in subsequent iterations sequentially" — don't try to build all 12 in one day.

---

## §8 — Four-layer persistence (file system)

| Layer | File | Purpose | Who edits |
|---|---|---|---|
| **Identity** | `docs/auto-go-soul.md` | Who I am, what I value, what I won't do | User only |
| **Wisdom** | `docs/auto-go-memory.md` | Compressed lessons from prior iterations, per-area notes | Agent (selectively, criteria in soul §STEP 6.c) |
| **State** | `docs/auto-go-heartbeat.md` | Per-iteration cursor, lock, log lines | Agent (every iteration) |
| **Focus** | `docs/auto-go-todo.md` | Owner-pinned items + carry-overs + agent-discovered | User (top section) + Agent (carry-overs + discoveries) |

Plus the user-level `~/.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/` directory — one file per learned behavior or feedback. Index in `MEMORY.md` at the top of that directory. Read those files as needed; they're short and specific.

**STEP 0 of every AUTO GO iteration reads soul + memory + todo + heartbeat in that order.** This is wired into `~/.claude/commands/auto-go.md`. Don't change the order — it's deliberate (identity → wisdom → focus → state).

---

## §9 — Critical rules (distilled — break any of these and quality regresses fast)

1. **Never edit `docs/auto-go-soul.md` without owner request.** Soul is the user's to author; you read it.
2. **Never silently apply unplanned improvements.** If you find something not in a plan and want to fix it, ask via Q&A: keep & develop now / remove for now / plan for later. (`feedback_unplanned_improvements.md`)
3. **Never hardcode user IDs.** No `created_by: 1`, no `userId: 0`. Always flow real `userId` from session. (`feedback_hardcoded_user_ids.md`)
4. **Always filter both `is_active` AND `deleted_at` on soft-deletable tables.** Independent flags. Reports/historical-data exempt. (`feedback_deleted_at_defense_in_depth.md`)
5. **Verify SQL columns against `AppDatabase+Migrations.swift`.** Many "obvious" column names are wrong (e.g., `users.display_name` not `first_name`). 64+ historical bugs from this. The `parts-sql-schema-checker` skill helps. (`feedback_sql_patterns.md`)
6. **Issue ordering:** sort `--sort created --order asc`, then bubble T1/T2 to top. Never use API default order. Every issue must have a tier tag; backfill before sorting. (`feedback_issue_ordering.md`)
7. **Session branch hygiene:** start + end on `main`. Feature-branch checkouts allowed mid-session for verification, but switch back BEFORE writing the closing heartbeat log line. (`feedback_session_branch_hygiene.md`)
8. **Direct Swift edits over Xcode prompts** for non-visual bugs/fixes. Xcode AI is only for UI-heavy visual work. (`feedback_direct_swift_edits.md`)
9. **Don't @copilot in issue bodies — assign instead.** The Copilot Coding Agent picks up by assignment, and `@copilot` in the body confuses it. Reviews use the Request-Review feature, not `@copilot apply` comments. (`feedback_copilot_delegation_workflow.md`)
10. **No skipping pre-commit hooks. No `--no-verify`. No `--no-gpg-sign`.** No force-pushing to `main`. (Standing CLAUDE.md rule.)

---

## §10 — Pre-beta posture (the load-bearing constraint)

From `feedback_release_state.md`:

> App is in development stage preparing for BETA release. Beta testers will be real users. Architecture-correctness worth the time NOW (pre-beta is cheaper than post). Pilot patterns before scaling. Data-loss bugs matter; visual polish can wait. Pattern quality matters because it's public-bound.

**Operational test:** before doing any work, ask "is this cheaper now or after beta testers have data?" If after, defer it. If now, do it.

**What this means for trade-offs:**
- Schema migrations: do them now. SQLCipher, per-field timestamps, `color_brand_skus` — all pre-beta.
- Visual polish: defer unless it blocks usability.
- Data-loss bugs (dismiss safety, save-and-exit, sync edge cases): always priority 1.
- Performance polish (filter-in-body, missing indexes, main-thread DB): pre-beta.
- Speculative features not on a plan: file Q&A, don't build.

---

## §11 — Reference map (where to read deeper)

### Project root
- `CLAUDE.md` — codebase standing instructions (mirrored as `copilot-instructions.md`, `AGENTS.md`, `GEMINI.md`)
- `Package.swift` — SwiftPM dependencies

### Docs
- `docs/auto-go-soul.md` — **identity**
- `docs/auto-go-memory.md` — **compressed wisdom**
- `docs/auto-go-heartbeat.md` — **state cursor** (huge log; read frontmatter only by default)
- `docs/auto-go-todo.md` — **focus / owner-pinned**
- `docs/dev-pipeline.md` — master pipeline tracker
- `docs/dev-qa.md` — Q&A (owner input)
- `docs/hunt-fix-tracker.md` — bug tracker
- `docs/usability-tracker.md` — UX issues tracker
- `docs/page-rebuild-tracker.md` — per-page rebuild tracker
- `docs/issue-closure-audit-tracker.md` — verifier output
- `docs/automation-recommendations.md` — scanner-recommendation queue
- `docs/auto-go-metrics.md` — Sunday self-improve data source
- `docs/auto-go-self-improvements.md` — Sunday self-improve mutation log
- `docs/plans/*.md` — design source-of-truth (read before coding any feature)
- `docs/DevTODO/*.md` — handoff tasks for the user

### User-level memory
- `~/.claude/projects/-Users-IA-GitHub-Weird-Part-Run-2/memory/MEMORY.md` — index
- `~/.claude/projects/.../memory/user_background.md` — user comm style
- `~/.claude/projects/.../memory/feedback_*.md` — behavior notes (12+ files; read as needed)

### Skills + commands
- `~/.claude/commands/auto-go.md` — AUTO GO command body (the loop spec)
- `~/.claude/commands/hunt-fix.md` — HUNT FIX command body
- `~/.claude/commands/github-flow.md` — GITHUB FLOW command body
- `~/.claude/scheduled-tasks/{name}/SKILL.md` — individual scanner / agent skills
- `~/.claude/hooks/parts-sql-check.sh` — PostToolUse SQL validator hook

### Xcode AI
- `xcode-ai/xcode.md` — instruction file for Xcode AI (separate from CLAUDE.md)
- `xcode-ai/fix-prompts/00-fix-order.md` — prompt queue tracker
- `xcode-ai/fix-prompts/*.md` — active prompts
- `xcode-ai/fix-prompts/done/` — archived

### GitHub
- Repo: `xXKillerNoobYT/Weird-Part-Run-2`
- State repo: `xXKillerNoobYT/ai-agent-Overall-manger` (private; GITHUB FLOW state)

---

## §12 — Day 1 checklist

Run these in order. Each takes < 10 minutes.

- [ ] Read this file top-to-bottom.
- [ ] Read `CLAUDE.md`, `docs/auto-go-soul.md`, `docs/auto-go-memory.md` (last sections — most recent rotation).
- [ ] `git status` — should be clean. If not, investigate before doing anything.
- [ ] `git log --oneline -10` — orient on the last 10 commits. Look for AUTO GO patterns.
- [ ] `gh issue list --state open --limit 100 | head -40` — see what's queued.
- [ ] `gh pr list --state open` — note which PRs are Copilot-authored, which are security.
- [ ] `cd core && swift test 2>&1 | tail -3` — verify tests pass on `main`. (~1300+ green.)
- [ ] `swift build 2>&1 | grep -c "warning:"` — should be 0.
- [ ] Read the Pending Questions section of `docs/dev-qa.md`. If non-empty, ratify with the user via AskUserQuestion (cluster batches of 4) BEFORE doing area work.
- [ ] Read `docs/auto-go-heartbeat.md` frontmatter. Note `current_area`, `iteration_count`, `current_area_checklist`.
- [ ] If `current_area_checklist` has any `done`-but-not-graduated, run that area's first pending check.
- [ ] At end of day: write a memory entry to `docs/auto-go-memory.md` ONLY if you learned something significant (criteria in soul STEP 6.c).
- [ ] Verify a clean commit landed for whatever you did, OR explicitly note the working tree is dirty and why.

If anything in this checklist confuses you, ask the user before guessing. The user prefers "I don't know yet" over silent guesses.

---

## §13 — 30 / 60 / 90-day milestones

### Day 30 (≈ 2026-06-07)
- Inventory area graduates rotation 6 (currently iteration 5/17).
- All 12 approved scanners are built + first project-wide runs done; their findings filed as area-tagged issues.
- SQLCipher migration PR #320 lands; CodeQL email issues close.
- Per-field LWW timestamps migration shipped on at least one pilot table; remaining ~34 tables planned.

### Day 60 (≈ 2026-07-07)
- Per-field LWW timestamps migration complete across all ~35 synced tables.
- Pagination Phase 2 audit complete (`docs/pagination-audit.md` exists with full call-site classification).
- Pagination Phase 3 cursor cutover started (≥ 50% of marked call sites converted).
- Dismiss-safety smart-patcher script run; ~30 sheets patched; #143 closes.
- #149 keyboard-dismiss campaign Phase 2 starts.
- All 14 areas have graduated at least once on the current rotation.

### Day 90 (≈ 2026-08-07)
- Pagination Phase 3 complete.
- #149 keyboard-dismiss campaign complete.
- All P0/P1 audit issues closed.
- TestFlight beta build shipped to first beta tester.
- Beta-readiness gate: all 8 success criteria from §1 satisfied.
- Q&A backlog at 0 the day of beta launch.

---

## §14 — How to talk to the user (TL;DR)

- **Plain English. Dashboards. Tables.** The user does not read code.
- **AskUserQuestion for choices.** Always include "Keep / Needs adjustment / Different" or "APPROVE / DEFER / REJECT" options. Batch by cluster, max 4 per call.
- **Insights blocks** when you make a non-obvious decision: 2–3 educational points specific to this codebase, in `★ Insight ─────────` format.
- **Concise summaries.** End with a dashboard, not prose. "What's done / What's next / What needs your input."
- **Trigger phrases the user uses:** `AUTO GO`, `AUTO GO STOP`, `AUTO GO RESUME`, `HUNT FIX`, `HUNT FIX STOP`, `HUNT FIX RESUME`, `GITHUB FLOW`, `AUTO GO STATUS`. Recognize and act on them.
- **Course corrections are normal.** The user pivots mid-session sometimes. Treat it as input, not interruption.
- **When something's already done:** verify in code (file:line) before claiming done. Don't trust trackers blindly.
- **When you find something out-of-scope:** file a GitHub issue with the right area + tier label. Don't lose the finding. Don't try to fix it now.

---

## §15 — Final note from Claude

Paperclip — the most valuable thing you'll inherit isn't the codebase or the workflow files. It's **the discipline that built them.** Plans before prompts. Slow over fast. Convergence over breadth. No finding gets lost. Per-POV per-question. Test before graduate. Pre-beta correctness over post-beta cleanup.

The user trusts agents that follow that discipline. Trust is hard to rebuild once spent. The first iteration where you skip a check to look productive is the iteration where the loop starts to drift.

Good luck. Ship the beta.

— Claude (final session, 2026-05-08)
