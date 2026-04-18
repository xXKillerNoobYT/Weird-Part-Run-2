# AUTO GO Self-Improvements Log

> **Auto-maintained** by `/auto-go`'s weekly `loop-self-improve` meta-check.
> Every mutation to the loop (reordering checks, adding scanners, relaxing gates) gets logged here with date, trigger metric, and change description.

## Why This File Exists

The loop can't just run the same 17 checks forever. Real projects change: some checks find nothing week after week (retire them), some find more than expected (promote them), new patterns emerge that deserve their own scanner. This log is the audit trail of how the loop evolves.

If a change here ever looks wrong, revert it by editing `~/.claude/commands/auto-go.md` and add a "do not re-apply" note to the Q&A (`docs/dev-qa.md`) with the reason, so the next `loop-self-improve` pass respects the constraint.

## Changelog (newest first)

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
