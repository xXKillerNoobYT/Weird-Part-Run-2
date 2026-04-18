# AUTO GO + Hunt-Fix Loop — Unified Autonomous Development Routines

> **Status:** Active (installed 2026-04-17)
> **Replaces:** 11 separate cron-scheduled tasks (hunt-fix-verify, test-coverage-maintenance, plan-enforcer, dev-improvement-scanner, dev-pipeline-manager, github-issues-sync, usability-enforcer, page-rebuild-enforcer, github-sync-and-review, weekly-cleanup, issue-closure-verifier)
> **Canonical plan-file location:** this file; mirror at `/Users/IA/.claude/plans/i-want-to-swich-inherited-pumpkin.md`
> **Related plans:** `production-readiness.md`, `cross-platform-qa.md`, `security-review.md`, `performance-review.md`

---

## What This Does (Plain English)

Two autonomous routines run the WiredPart beta-to-production push:

1. **AUTO GO** — a master orchestrator that rotates through every type of maintenance/development work (bug-hunting, test-coverage, plan-alignment, usability, page-rebuild, GitHub sync, production-readiness, cross-platform-QA, security, performance). One firing runs ONE task. The next firing picks up where the last one left off.
2. **Hunt-Fix Loop** — a dedicated bug-exterminator that only runs the hunt-fix-verify scanner suite. Runs on an offset cadence so it never collides with AUTO GO.

Both routines:
- Start automatically each morning at 6:00 AM (AUTO GO) and 6:07 AM (Hunt-Fix)
- Fire every 15 minutes through the day (6 AM → 10:45 PM local)
- Can be triggered manually from any chat by typing `AUTO GO` or `HUNT FIX` (also `/auto-go`, `/hunt-fix`)
- Can be paused with `AUTO GO STOP` / `HUNT FIX STOP` and resumed with `AUTO GO RESUME` / `HUNT FIX RESUME`
- Stop overnight (no firing 11 PM — 6 AM)

## Why We Need This

Before: 11 separate cron slots, one per task, each firing at a fixed time regardless of whether work was waiting. Silent failures broke the day. No global "is the loop alive?" view.

After: one heartbeat, one dispatcher, one state file per routine. The loop knows what ran last and picks the most useful next task. Failures are visible in the heartbeat file. The user can pause/resume from any chat.

## Current State

- 11 scheduled tasks exist at `~/.claude/scheduled-tasks/*/SKILL.md` — their **prompt bodies are reused verbatim**; only their individual cron triggers are disabled.
- Trackers continue to be the source of truth: `docs/dev-pipeline.md`, `docs/hunt-fix-tracker.md`, `docs/usability-tracker.md`, `docs/page-rebuild-tracker.md`, `docs/issue-closure-audit-tracker.md`, `docs/dev-qa.md`.
- Q&A workflow (design questions → `docs/dev-qa.md`) and Xcode-prompt workflow (UI work → `xcode-ai/fix-prompts/`) are preserved as the two escalation paths when the loop hits work it cannot do autonomously.

## Proposed Changes

### Files Created

**Slash commands (user-scoped, work from any chat):**
- `~/.claude/commands/auto-go.md` — master dispatcher
- `~/.claude/commands/hunt-fix.md` — hunt-fix-loop runner (path-agnostic)
- `~/.claude/commands/auto-go-stop.md` — sets stop flag
- `~/.claude/commands/auto-go-resume.md` — clears stop flag
- `~/.claude/commands/auto-go-status.md` — prints heartbeat state

**New sub-routine SKILL.md files (dispatched by AUTO GO):**
- `~/.claude/scheduled-tasks/production-readiness/SKILL.md`
- `~/.claude/scheduled-tasks/cross-platform-qa/SKILL.md`
- `~/.claude/scheduled-tasks/security-review/SKILL.md`
- `~/.claude/scheduled-tasks/performance-review/SKILL.md`

**State files (gitignored):**
- `docs/auto-go-heartbeat.md`
- `docs/hunt-fix-heartbeat.md`

**Hook:**
- `~/.claude/settings.json` — `UserPromptSubmit` hook maps exact phrases to slash commands.

### Scheduled Task Registration

Via `mcp__scheduled-tasks__create_scheduled_task`:

| taskId | cronExpression | prompt |
|---|---|---|
| `auto-go-loop` | `*/15 6-22 * * *` | "Run one iteration of `/auto-go`." |
| `hunt-fix-loop-heartbeat` | `7,22,37,52 6-22 * * *` | "Run one iteration of `/hunt-fix`." |

### Existing Scheduled Tasks — Disabled (Not Deleted)

11 tasks set `enabled: false` via `mcp__scheduled-tasks__update_scheduled_task`. Their SKILL.md files remain on disk; AUTO GO dispatches to the prompt bodies.

## Data Flow (One AUTO GO firing)

1. Cron fires at e.g. 9:15 AM.
2. Scheduled task executes its prompt: "Run one iteration of `/auto-go`."
3. The `/auto-go` slash command loads.
4. Command reads `docs/auto-go-heartbeat.md`:
   - Checks `stop_flag` — if set, log "paused" and exit.
   - Checks `in_progress` — if set, log "skipped (previous iteration still running)" and exit.
   - Reads `last_task` and picks the next task from the priority queue.
5. Sets `in_progress: true` in the heartbeat file (atomic rename).
6. Reads the target `~/.claude/scheduled-tasks/{taskId}/SKILL.md` and follows its instructions verbatim.
7. Updates the relevant tracker file (`docs/hunt-fix-tracker.md` if it was hunt-fix-verify, etc.).
8. Clears `in_progress`, updates `last_task` and `last_run` timestamp, increments `iteration_count`.
9. Logs a one-line summary in the heartbeat file's human-readable log.
10. Exits. Next firing in 15 min.

## Task Rotation Priority Queue

| Order | Task | Notes |
|---|---|---|
| 1 | `hunt-fix-verify` | Always first slot of the morning |
| 2 | `test-coverage-maintenance` | |
| 3 | `plan-enforcer` | |
| 4 | `dev-improvement-scanner` | |
| 5 | `dev-pipeline-manager` | Generates Q&A, surfaces blockers |
| 6 | `github-issues-sync` | |
| 7 | `usability-enforcer` | |
| 8 | `page-rebuild-enforcer` | |
| 9 | `usability-hunter` | |
| 10 | `production-readiness` | NEW |
| 11 | `cross-platform-qa` | NEW |
| 12 | `security-review` | NEW |
| 13 | `performance-review` | NEW |
| 14 | `github-sync-and-review` | Only runs at ≥21:00 local |
| Sun | `weekly-cleanup` | Interleaved Sunday mornings |
| Sun | `issue-closure-verifier` | Interleaved Sunday mornings |

Idempotency: each task checks its own tracker for "last ran within 1 hour?"; if yes, skip and advance to the next in the queue.

## Escalation Paths (Preserved)

- **Design questions** → appended to `docs/dev-qa.md`. Heartbeat logs "blocked on Q&A #N". Loop advances to the next task — does not spin on the blocked item.
- **iOS UI work** → Xcode prompt written to `xcode-ai/fix-prompts/`, `00-fix-order.md` updated. Heartbeat logs "deferred to PE-XXX". `issue-closure-verifier` picks up closure later.
- **Out-of-reach tasks** (native device testing, App Store Connect, financial actions, destructive migrations) → `docs/DevTODO/` task file with instructions + optional AI prompt. User tags `done` when complete.

## Test Plan

See the verification section of `/Users/IA/.claude/plans/i-want-to-swich-inherited-pumpkin.md` (11 steps covering manual triggers, stop/resume, morning kickoff, rotation, collision avoidance, escalation paths, cron registration).

## User Roles Affected

- **Owner:** gains a single kill-switch (`AUTO GO STOP`) and a single status view (`/auto-go-status`). Replaces 11 separate schedules to remember.
- **Developer (the user):** types `AUTO GO` from any chat to force-kick a cycle. Gets Q&A and Xcode prompts filed automatically when the loop needs input.
- **Other agents:** existing 11 SKILL.md files continue as-is. Only their individual cron triggers are disabled.

## Security Considerations

- State files (`docs/auto-go-heartbeat.md`, `docs/hunt-fix-heartbeat.md`) are gitignored so they don't leak local run history.
- Trigger phrase hook uses anchored regex (`^…$`) so a stray "AUTO GO" inside a larger message won't fire.
- Destructive operations (commits, pushes, issue closures) still go through existing guardrails in the individual SKILL.md bodies — dispatcher adds no new privileges.

## Apple HIG Notes

N/A (this is an orchestration-layer change, no iOS UI impact).
