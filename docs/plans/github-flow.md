# GITHUB FLOW — Third Autonomous Routine

> **Status:** Active (installed 2026-04-18)
> **Role:** Handles external GitHub activity — comments, reviews, issues, PRs, Copilot coordination, security alerts
> **Siblings:** AUTO GO (area-focused development), HUNT FIX (bug extermination)
> **Shared identity:** reads the same `docs/auto-go-soul.md` and `docs/auto-go-memory.md` as AUTO GO

---

## What This Does (Plain English)

While AUTO GO focuses on one code area at a time and HUNT FIX exterminates bugs, GITHUB FLOW **keeps the project moving from the outside** — the parts that live on github.com rather than in the local working tree:

- **Reads new comments** on issues and PRs. Responds, applies simple changes, escalates design questions to Q&A.
- **Triggers `@copilot`** when conditions warrant (merge conflicts on an approved PR, explicit user instruction, large PR needing review).
- **Runs code review** on open PRs via the `/code-review:code-review` skill.
- **Handles security alerts** — Dependabot, CodeQL, secret scanning. Critical → urgent DevTODO. Low → noted and tracked.
- **Manages issue hygiene** — stale issues nudged or closed, missing area labels added, duplicates linked + closed.
- **Auto-merges** approved green PRs (only after user-approval via Q&A — never autonomously).

## Why We Need This

**Before:** A user comment on an open issue might sit for hours until the next `github-issues-sync` pulse. Copilot never got triggered by the agent — the user had to remember to type `@copilot`. Merge conflicts piled up on PRs. Dependabot alerts got ignored.

**After:** Every 30 minutes (twice an hour), GITHUB FLOW scans GitHub activity, responds to what can be handled, escalates what needs decisions, and surfaces what needs human attention. The user's project keeps moving even when they're not looking at it.

## Current State

- `github-issues-sync` SKILL.md exists but was disabled when AUTO GO installed. It only pulled new issues; it did not read comments, handle PRs, or trigger Copilot.
- `/code-review:code-review` plugin skill exists from the `pr-review-toolkit` plugin — GITHUB FLOW chains it.
- `gh` CLI is available and authenticated.
- No current routine handles comment replies, Copilot triggers, or Dependabot alerts autonomously.

---

## Design

### Schedule

| Routine | Cron | Cadence |
|---|---|---|
| AUTO GO | `3,18,33,48 6-22 * * *` | every 15 min |
| HUNT FIX | `10,25,40,55 6-22 * * *` | every 15 min (offset 7 min) |
| **GITHUB FLOW** | `13,43 6-22 * * *` | **every 30 min** (3 min after HUNT FIX slots) |

The 3-min offset from HUNT FIX ensures HUNT FIX's iteration has finished before GITHUB FLOW starts. Both stop overnight (6 AM – 10:45 PM window).

### Invocation paths

1. **Automatic** — scheduled-task cron (primary).
2. **Manual slash** — `/github-flow` in any chat.
3. **Trigger phrase** — `GITHUB FLOW` or `GIT FLOW` typed in any chat (via the UserPromptSubmit hook).
4. **Stop/Resume** — shares `AUTO GO STOP` / `AUTO GO RESUME` with the other two routines. One kill switch for all three.

### Heartbeat state

File: `docs/github-flow-heartbeat.md` (gitignored, same pattern as other routines).

Frontmatter tracks:
- `stop_flag`, `in_progress`, `last_run`, `iteration_count`, `day_started_at` (operational, same as AUTO GO)
- `last_subtask` — which of the 5 sub-tasks ran last (rotation)
- `last_comment_cursor` — timestamp of the newest comment processed (so next run only pulls newer ones)
- `last_copilot_trigger_at` — earliest time another trigger can fire (rate-limiting)
- `copilot_triggers_today` — count, capped at 10/day
- `last_security_sweep_at` — security sub-task throttle
- `last_pr_review_at` — PR review sub-task throttle

### Scope — ALL branches, not just main

This is key to why GITHUB FLOW is its own routine: it works across the **entire branch graph** of the repo, not just whatever AUTO GO is focused on locally. AUTO GO is working-tree-centric; GITHUB FLOW is repo-centric.

Branches GITHUB FLOW attends to:
- **`main`** — the default branch. Issues, CI, security alerts on main.
- **Open PR branches** — by me, by the user, by collaborators, by Copilot. Reviews, comments, merge conflicts, CI status.
- **Feature branches without a PR** — detected via "commits ahead of main, no PR". Prompt to open a PR, or mark stale.
- **Copilot-authored branches** — usually prefix `copilot/` or similar. Special handling: verify Copilot is actively working (or needs nudging).
- **Release / hotfix branches** — if present. Flag for manual handling (don't autonomously touch release branches).

This multi-branch scope is specifically why this is a routine: any branch can have activity at any time, and routing all of that through AUTO GO (which is single-area-focused) would either starve it or break its convergence.

### Sub-task rotation

Each firing picks ONE sub-task based on rotation + throttles (except SA which always runs):

| # | Sub-task | Cadence | What it does |
|---|---|---|---|
| SA | **Triage new activity** | every run (always) | Pulls new comments + PR events since `last_comment_cursor` — across ALL branches. Responds or escalates. |
| SB | **PR review sweep** | every ~4 runs (throttled ~2h) | Lists open PRs across all branches, runs `/code-review:code-review` on unreviewed ones, posts findings, checks merge conflicts. |
| SC | **Security sweep** | every ~8 runs (throttled ~4h) | Pulls Dependabot + CodeQL + secret-scanning alerts (branch-aware — some target specific branches). |
| SD | **Issue hygiene** | every ~8 runs (throttled ~4h) | Stale nudges, missing labels, duplicate detection, orphan fix (repo-wide). |
| SF | **Branch health** | every ~12 runs (throttled ~6h) | Lists ALL branches, finds: feature branches without PRs, stale branches (14+ days), branches behind main, Copilot branches needing nudge. |
| SE | **Copilot coordination** | triggered by SA/SB/SF findings, throttled | Posts `@copilot` instructions when conditions match (governance below). |

SA always runs. SB/SC/SD/SF run when their throttle windows have elapsed. SE runs inline when another sub-task surfaces a Copilot-eligible situation.

### @copilot trigger governance (CONSERVATIVE — key areas only)

Copilot costs credits and is publicly visible on the repo. The default is **do not trigger**. Every potential trigger is filed as a Q&A in `docs/dev-qa.md` and waits for user APPROVE/DEFER/REJECT — with **one narrow exception** below.

**The one auto-fire case (Tier 1 — very rare):**
- A user comment in the thread already contains an explicit `@copilot <instruction>` they wrote themselves
- AND Copilot has not responded in 60+ minutes
- AND this specific user-authored instruction hasn't been restated in the last 24 hours
- → Restate the instruction verbatim so Copilot picks it up

This case auto-fires because the user has already explicitly requested Copilot; I'm just making sure it was received. I am not originating the trigger.

**Everything else goes through Q&A (Tier 2):**
- Merge conflicts on a PR — file Q&A asking "trigger `@copilot resolve the merge conflicts` for #N? It's a {tiny/moderate/large} conflict in {paths}."
- Code review request on an open PR — file Q&A
- Refactor suggested by a reviewer — file Q&A
- Any ambiguity about whether it's "key area" — file Q&A

**Never auto-fire (Tier 3):**
- Triggers that could merge to `main` without human review
- Triggers that could spend money
- Triggers that change access control, secrets, or CI/CD config

### What counts as a "key area"

Even after user approval, the set of reasonable Copilot triggers is narrow. Rough guide (will be refined via memory over time):

| Key area | Copilot appropriate? |
|---|---|
| Large refactor across 20+ files | Yes — if user approves |
| Merge conflict resolution | Yes — if user approves (Tier 2) |
| Major feature implementation | Maybe — depends on user preference |
| iOS UI (SwiftUI) | No — Xcode AI handles these via prompts |
| Simple bug fix (< 50 lines) | No — AUTO GO handles directly |
| Routine comment reply | No — I reply directly |
| Dependabot minor/patch | No — auto-merge question, not Copilot |
| Security-critical (auth, keychain, secrets) | No — user handles directly; I just flag |

When in doubt, **don't trigger**. A user can always type `@copilot ...` themselves; I should err on the side of silence.

### Rate limits (belt-and-suspenders, on top of Q&A gating)

- Max 1 Copilot-restate per thread per 24 hours
- Max 3 restates per day across the whole repo (not 10 as originally drafted — too aggressive)
- Dedupe: skip if Copilot has already commented in the last 60 min
- If the Tier-1 auto-fire case triggers 3+ times in one week without Copilot ever responding successfully, stop auto-firing it and file a Q&A asking whether Copilot is actually wired up for this repo.

All considered-triggers logged to `docs/github-flow-tracker.md` — both fired and not-fired, with reasoning. This gives the user a clear audit trail of when the routine almost triggered and why it didn't.

### Response behavior for human comments

When SA encounters a new human comment:

1. **Pending-Q&A answer** (comment on an issue referenced in `docs/dev-qa.md`, user answered a pending question):
   - Update `docs/dev-qa.md` with the answer
   - Notify AUTO GO by writing to `docs/auto-go-memory.md` "Things I know about the user's working style"
   - Post a short confirmation comment: "Captured — AUTO GO will act on this next iteration."

2. **Design question** (user asked something about scope/behavior):
   - Rewrite as a Q&A entry in `docs/dev-qa.md` with 3–5 role perspectives
   - Comment back: "Filed as Q&A. The answer will flow into the plan."

3. **Apply-this-change request** (user said "fix this", "apply these", "implement this"):
   - If simple + scoped → commit the change inline and comment with the SHA
   - If larger → file a plan-stub in `docs/plans/` and a Q&A for the details
   - If needs iOS UI → Xcode prompt in `xcode-ai/fix-prompts/`

4. **@copilot mention:**
   - Tier 1 auto-fire → restate cleanly
   - Tier 2 → file Q&A
   - Tier 3 → comment "I need user approval before firing this Copilot trigger. Filed as Q&A."

5. **Bot comment (Dependabot, CodeQL, SecurityBot):**
   - See Sub-task SC below

6. **Ambiguous / I-don't-know:**
   - File a Q&A: "Got this comment on #N — how should I respond?"

### Stop/Resume shared with AUTO GO

`AUTO GO STOP` sets `stop_flag: true` in all three heartbeat files (auto-go, hunt-fix, github-flow). `AUTO GO RESUME` clears all three. One switch kills everything.

Separate stop of just GITHUB FLOW: `GITHUB FLOW STOP` / `GITHUB FLOW RESUME` — operates on `docs/github-flow-heartbeat.md` only.

---

## Files to Create

- `~/.claude/commands/github-flow.md` — the slash command / iteration runner
- `docs/github-flow-heartbeat.md` — state file (gitignored)
- `docs/github-flow-tracker.md` — audit log of every action taken (committed — valuable history)
- Scheduled task registered via MCP: `github-flow-loop`
- `.gitignore` — add `docs/github-flow-heartbeat.md`
- Update to `~/.claude/hooks/auto-go-trigger.sh` — add `GITHUB FLOW` / `GIT FLOW` / `GITHUB FLOW STOP` / `GITHUB FLOW RESUME` phrases

## Files to Modify

- `~/.claude/projects/.../memory/auto-go-loop-architecture.md` — document the third routine
- `~/.claude/projects/.../memory/MEMORY.md` — update the Autonomous Development section
- `CLAUDE.md` — add the new trigger phrases
- `docs/auto-go-soul.md` — note HUNT FIX and GITHUB FLOW as siblings (soul is shared)

---

## Reused building blocks

- `/code-review:code-review` (plugin skill) — used by SB
- `gh` CLI for all GitHub API interactions
- `/claude-automation-recommender` — may be invoked when SC or SD surface repeated patterns worth automating
- Existing `docs/dev-qa.md` Q&A format — used for all user-approval-gated actions
- Existing `docs/DevTODO/` format — used for critical security DevTODOs
- Shared soul + memory files

---

## Verification (end-to-end)

1. Type `GITHUB FLOW` in a fresh chat — runs one iteration, reports what it saw and did.
2. Comment on an open issue from another account — next iteration should read it and log in the tracker.
3. Open a PR with a merge conflict — next iteration should post `@copilot resolve the merge conflicts in this pull request`.
4. Type `AUTO GO STOP` — next github-flow firing should log "STOPPED — shared stop flag set" and do nothing.
5. Type `GITHUB FLOW STOP` — same behavior but scoped to just this routine.
6. Verify `mcp__scheduled-tasks__list_scheduled_tasks` shows `github-flow-loop` enabled with cron `13,43 6-22 * * *`.

---

## Risks and mitigations

- **Rate limiting on GitHub API** — `gh api` hits rate limits. Mitigation: cursor-based incremental pulls (only fetch since `last_comment_cursor`), not full rescans.
- **Triggering Copilot too aggressively** — burn user's API credits. Mitigation: tiered governance (above) + daily cap (10/day) + per-PR cap (1/day).
- **Bot responding to bots** — Dependabot comments, security bot comments. Mitigation: explicit filter in SA that identifies bot authors and routes to SC handler, not the general reply handler.
- **Posting public comments on private work** — comments are visible to everyone with repo access. Mitigation: all comment bodies reviewed for sensitive info (no file paths that could leak secrets, no API keys, etc.) before posting.
- **Merge authority** — auto-merging could ship broken code. Mitigation: Tier 3 rule — merging to `main` never autonomous; always requires user approval via Q&A.
