# AUTO GO Self-Improvements Log

> **Auto-maintained** by `/auto-go`'s weekly `loop-self-improve` meta-check.
> Every mutation to the loop (reordering checks, adding scanners, relaxing gates) gets logged here with date, trigger metric, and change description.

## Why This File Exists

The loop can't just run the same 17 checks forever. Real projects change: some checks find nothing week after week (retire them), some find more than expected (promote them), new patterns emerge that deserve their own scanner. This log is the audit trail of how the loop evolves.

If a change here ever looks wrong, revert it by editing `~/.claude/commands/auto-go.md` and add a "do not re-apply" note to the Q&A (`docs/dev-qa.md`) with the reason, so the next `loop-self-improve` pass respects the constraint.

## Changelog (newest first)

### 2026-04-18 — First approved-recommendation build (PartsService SQL column validator hook)
- **Trigger:** Q&A #1 in `Automation Recommendations — Parts Area (2026-04-18)` cluster answered APPROVE.
- **Changes:**
  - Created `/Users/IA/GitHub/Weird-Part-Run-2/.claude/hooks/parts-sql-check.sh` — bash script that greps PartsService/PartsModels edits for 10 known-bad SQL column patterns (sourced from `memory/feedback_sql_patterns.md`).
  - Wired into `.claude/settings.local.json` under `hooks.PostToolUse` with matcher `Edit|Write`.
  - Closed GitHub issue [#255](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/255).
  - Removed rejected `parts-xcode-phase2-generator` recommendation from `docs/automation-recommendations.md` (per Q&A #3 REJECT).
  - Updated the recommendations summary table with APPROVE/REJECT/DEFER statuses.
- **Rationale:** User introduced the approval-gated automation workflow earlier this session. This is the first recommendation to go through the full discover → Q&A → approve → build cycle. Pattern confirmed working: the hook is live on this machine, future edits to PartsService will get the SQL column warning trail.
- **Non-obvious detail:** Initial hook regex matched `uh.deleted_at` (user_hats, which DOES have deleted_at) as a false positive for the `h.deleted_at` pattern. Fixed with `(^|[^_[:alnum:]])h\.deleted_at` to require a non-alphanumeric prefix. Lesson: SQL column validators need to distinguish table aliases carefully.

### 2026-04-18 — Approval-gated automation workflow + periodic github-issues-sync (user directive)
- **Trigger:** user directive ("apply the automation recomindashions every so often yourself once it's aproved... make sure to do a github issue sysce every so often as well as part of this loop").
- **Changes:**
  - C13 reworked into a 2-phase discover→Q&A→implement flow. Recommendations are no longer auto-applied; each is filed as a Q&A with APPROVE/DEFER/REJECT.
  - New throttled meta-check: global `github-issues-sync` every ~4 hours (tracked via `last_meta_github_sync_at`).
  - Updated `/auto-go.md` Phase 2 rule: on failure, file another Q&A rather than silently skipping.
  - First global sync caught useful drift: `parts-sql-schema-checker` (recommended #2) was already CLOSED as #254 and the skill was installed — Q&A updated to reflect.
- **Rationale:** autonomy and safety need to coexist. The user approves, I implement, failures surface as new questions.

### 2026-04-18 — Initial loop expansion (manual, not from self-improve)
- **Trigger:** user feedback — "make sure AUTO GO is smart; find gaps in plan, gaps in code vs plan, other smart things; find more things to automate; self-improve its workflow over time"
- **Changes:**
  - Expanded checklist from 12 → 17 items (added C1b plan-vs-code drift, C2b GitHub issue ingest, C7b dev-improvement polish, C11b process-gaps, C13 automation opportunities)
  - Added throttled meta-check `loop-self-audit` (Sunday mid-morning)
  - Added throttled meta-check `loop-self-improve` (Sunday afternoon) — this is the self-improvement feedback loop
  - Added metrics file `docs/auto-go-metrics.md` — raw data for self-improve analysis
  - Fixed skip-path bug: Gates A/B/D now preserve frontmatter (only log gets a new line)
- **Rationale:** the initial 12-check design was breadth but not depth; it didn't catch drift (planned feature missing in code), process stalls (Q&A pending forever), or close the self-improvement feedback loop.

### (future entries written automatically by loop-self-improve)
