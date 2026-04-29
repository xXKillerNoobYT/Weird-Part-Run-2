# AUTO GO — Active Todo List

> **Always-readable scratch board for what AUTO GO (or any agent) should do next.**
> Read first thing in any new agent session before AUTO GO's STEP 0 dives into soul/memory/heartbeat.
> Items here have priority over the area-rotation checklist when they conflict — these are owner-flagged or in-flight tasks.
>
> This file is the "today" lens. Long-term memory still lives in `docs/auto-go-memory.md`. Identity still lives in `docs/auto-go-soul.md`. Iteration-by-iteration state still lives in `docs/auto-go-heartbeat.md`.
>
> **Edit format:** plain markdown checklists. Owner adds `[ ]` items at top; agents check them `[x]` and append a one-line completion note. Agents may add `[ ]` items below `## Agent-discovered` when they need owner ratification or want to surface work for the next iteration.

---

## Owner-pinned (top of stack)

> Items the owner explicitly wants worked on next, regardless of area rotation. Empty when nothing is pinned.

- [ ] _(empty — owner adds `[ ]` items here when they want a specific task picked up first)_

## Active iteration carry-overs

> Work flagged as in-progress at the end of the previous AUTO GO iteration. Agent inspects this file before deciding whether to continue prior work or advance the rotation.

- [x] **2026-04-26 — Drive PR #321 (issue #282) to merge.** **DONE 2026-04-26T23:56Z** — squash-merged as commit 395c6a29 (203/8 across UserFriendlyError.swift + FleetService.swift + FleetServiceTests.swift). All 4 cleanup items landed via Copilot commits 8f0bcee7 + 21f48439 (trailer FK guard + userFriendlyError doc + flipped test + transfer_reason cap + 7th test). Post-merge: 1752 tests / 57 suites pass; build clean. CodeQL SUCCESS. Workflow validated end-to-end matches `feedback_copilot_delegation_workflow.md`.

- [ ] **2026-04-26 — Investigate stale Copilot branches.** Two orphan branches with no associated open PRs: `copilot/fix-bugs-in-code` (last commit 2026-04-26 00:56Z) and `copilot/refactor-sensitive-field-encryption` (2026-04-26 01:18Z). Likely abandoned Copilot attempts from prior delegations. **Don't delete blindly.** Run `gh api repos/xXKillerNoobYT/Weird-Part-Run-2/branches/<name> --jq '.commit'` + check if any closed PR points at them. If genuinely abandoned + no closed-PR backreference, delete with `git push origin --delete <branch>` to keep the branch list tidy.

## Agent-discovered (awaiting owner ratification or scheduling)

> Findings the agent surfaced that aren't blocking the current check but shouldn't be lost. These flow into the regular pipeline (`docs/dev-qa.md` for design questions, GitHub issues for bugs/improvements). This list is a short-term holding pen.

- [ ] **2026-04-25 — Manual-control switch + STEP 0.d wiring (for Sunday loop-self-improve to review).** User cancelled the `/loop 2h /auto-go` cron (job `7bc32584`) and reaffirmed manual control via trigger phrases. Two changes landed:
  1. Created `docs/auto-go-todo.md` (this file) as the fourth persistence layer alongside soul/memory/heartbeat.
  2. Edited `~/.claude/commands/auto-go.md` to add **STEP 0.d — Read the todo file** between 0.c and STEP 1, so every iteration reads owner-pinned items first.

  **What loop-self-improve should consider Sunday:**
  - Is the new STEP 0.d the right place, or should todo-reading happen even earlier (before soul) when an emergency owner-pin needs to override identity?
  - Should the todo file itself get a frontmatter for machine-parsable counters (e.g. `pinned_count`, `carryover_count`) so STATUS reports can summarize without reading the body?
  - Now that AUTO GO has 4 persistence files (soul, memory, heartbeat, todo), is the Sunday self-improve pass updating its analysis to consider all four, or only the original three?
  - The cron `7bc32584` cancellation was a session-only action (in-memory). The persistent cron schedule (6h cadence at 6/12/18 + 9/15/21) is unchanged. Confirm this matches owner intent on the next pass.

  When self-improve fires (Sunday afternoon iteration 9–16), it should append a decision/mutation to `docs/auto-go-self-improvements.md` and check this item off here.

## Manual control

> Trigger phrases the owner can type any time:
>
> - `AUTO GO` — fire one AUTO GO iteration immediately
> - `AUTO GO STOP` — pause both AUTO GO and HUNT FIX (sets stop_flag in both heartbeat files)
> - `AUTO GO RESUME` — clear stop_flag, resume on next scheduled fire
> - `HUNT FIX` — fire one HUNT FIX iteration (focused on AUTO GO's current area)
> - `HUNT FIX STOP` / `HUNT FIX RESUME` — same as above for HUNT FIX
> - `GITHUB FLOW` — fire portfolio overseer (cross-project sweep)
> - `AUTO GO STATUS` — read-only dashboard of current state
>
> The cron schedule is intentionally light: AUTO GO at 6AM/12PM/6PM local (`0 6,12,18 * * *`), HUNT FIX at 9AM/3PM/9PM (`0 9,15,21 * * *`). Manual triggers run on top.
>
> **Continuous /loop variants** (e.g. `/loop 2h /auto-go`) should only be set up by explicit owner request — they are not the default. The manual trigger pattern is the default.

---

*Seeded 2026-04-25 (when the manual-control mode was reaffirmed). Format stays minimal until accumulated use suggests sections to add.*
