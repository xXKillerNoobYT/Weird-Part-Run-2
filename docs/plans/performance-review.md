# Performance Review Scanner

> **Part of:** AUTO GO unified loop (see `auto-go-unified-loop.md`)
> **SKILL.md:** `~/.claude/scheduled-tasks/performance-review/SKILL.md`

## What This Does (Plain English)

Scans for common performance anti-patterns that cause slow queries, UI jank, and memory leaks. Focuses on files changed recently so it runs fast and finds regressions close to when they were introduced.

## Why We Need This

Performance regressions are easier to fix close to the commit that caused them. A nightly or even daily check is too coarse. Running performance-review as one slot in the AUTO GO rotation means we sweep the codebase frequently without any one pass being expensive.

## Current State

- No dedicated performance SKILL.md today.
- Some performance checks are informally handled by `dev-improvement-scanner` Phase D (UX) and by the existing test suite.
- No automated check for SQL `SELECT *` on large tables, N+1 patterns, heavy work on `.onAppear`, or bundle-size regressions.

## Proposed Changes

### SKILL.md content

Scanner phases:

**Phase A — Identify changed files**
```
cd /Users/IA/GitHub/Weird-Part-Run-2 && git log --since="7 days ago" --name-only --pretty=format: | sort -u | grep -E "\.(swift|ts|tsx|sql)$"
```

**Phase B — SQL anti-patterns**
- Grep changed Swift service files for `SELECT \*` on known-large tables (parts, jobs, movements, order_lines, messages, timesheets).
- Any SELECT without a WHERE on those tables → flag.
- `fetchAll` on tables with > 10k expected rows without LIMIT → flag.

**Phase C — N+1 query patterns**
- Read changed service files. Look for patterns like:
  ```swift
  let items = try db.fetchAll(...)
  for item in items {
      let detail = try db.fetchOne("SELECT ... WHERE id = ?", item.id)  // N+1!
  }
  ```
- Flag as "consider JOIN or IN clause".

**Phase D — Heavy work on `.onAppear`**
- Grep changed SwiftUI files for `.onAppear` followed by synchronous DB calls, network calls, or `for` loops over large collections.
- Suggest wrapping in `Task { }` or moving to `.task` modifier.

**Phase E — Blocking main thread**
- Grep for `DispatchQueue.main.sync` (almost always wrong).
- Grep for synchronous `FileManager` calls in UI paths.

**Phase F — React/Tauri-side perf**
- Grep changed `.tsx` for missing `useMemo`/`useCallback` on expensive computations inside render.
- Grep for `.map(...)` inside render creating new object/function identities each frame (can cause child re-renders).

**Phase G — Bundle size delta**
- `npm run build` (if applicable) → compare output size to stored baseline in `docs/performance-review-tracker.md`.
- Flag > 5% bundle size increase since last recorded baseline.

**Phase H — Memory leak heuristics**
- Grep Swift for `weak self` missing inside closures that escape (`@escaping`).
- Grep for `Timer.scheduledTimer` without `.invalidate()` in deinit.

**Phase I — File findings**
- Each finding → GitHub issue with label `performance` (check duplicates).
- Passing → logged to `docs/performance-review-tracker.md`.
- Heartbeat logs "performance-review: N findings".

## Files to Create

- `~/.claude/scheduled-tasks/performance-review/SKILL.md`
- `docs/performance-review-tracker.md` (seeded on first run, stores bundle-size baseline)

## Test Plan

1. First run: establishes bundle-size baseline.
2. Subsequent runs: flags regressions > 5%.
3. Introduce a SQL `SELECT *` on `parts`: scanner should flag it.
4. Introduce a `.onAppear` with a synchronous DB call: scanner should flag it.

## User Roles Affected

- **Developer:** catches perf regressions within ~1 day of commit.
- **End users:** app stays fast as it grows.

## Security Considerations

N/A.

## Apple HIG Notes

- HIG recommends views appear in < 400 ms. Phase D enforces this indirectly by flagging heavy `.onAppear` work.
