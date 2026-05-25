# Hunt-Fix-Verify Loop Plan

> **Created:** 2026-03-28
> **Status:** ACTIVE
> **Tracker:** `docs/hunt-fix-tracker.md`

## Context

The app has 65+ documented issues, unknown undocumented issues, and gaps between plans and code. We need a **mechanical process** — a machine that finds problems, fixes them, verifies the fixes, and repeats until nothing is left. The key insight: **we don't need to know all the problems upfront.** The loop discovers them as it runs.

---

## How The Loop Works

Think of it like a washing machine. It doesn't know how dirty the clothes are. It just runs cycles until they're clean.

```
         ┌───────────────┐
         │   START LOOP   │
         └───────┬───────┘
                 ▼
         ┌───────────────┐
         │    SCAN        │  ← Run every scanner. Collect a list.
         └───────┬───────┘
                 ▼
         ┌───────────────┐
         │  ISSUES = 0?  │──YES──▶ RUN FINAL VERIFY
         └───────┬───────┘              │
                NO                  Pass? ──YES──▶ DONE
                 │                      │
                 ▼                     NO
         ┌───────────────┐              │
         │  PICK TOP 5   │◀────────────┘
         └───────┬───────┘
                 ▼
         ┌───────────────┐
         │    FIX THEM   │
         └───────┬───────┘
                 ▼
         ┌───────────────┐
         │  TEST & BUILD │──FAIL──▶ (fix goes back in queue)
         └───────┬───────┘
                PASS
                 │
                 ▼
         ┌───────────────┐
         │ UPDATE TRACKER │  ← Mark fixed, update counts
         └───────┬───────┘
                 │
                 ▼
            (back to SCAN)
```

---

## The Scanners (What Runs Each Cycle)

These are the "eyes" of the loop. They don't fix anything — they just produce a list of problems. Each scanner is independent and can run in parallel.

### Scanner 1: Compile
- **Input:** Source code
- **Output:** List of compile errors and warnings
- **Command:** `cd core && swift build 2>&1`
- **Pass condition:** Zero errors AND zero warnings

### Scanner 2: Tests
- **Input:** Test suite
- **Output:** List of failing tests
- **Command:** `cd core && swift test 2>&1`
- **Pass condition:** ALL tests pass (currently 548, will grow)

### Scanner 3: Code Patterns
- **Input:** All `.swift` files in `core/Sources/` and `Weird Parts IOS/`
- **Output:** List of code smell locations
- **Scans for:**
  - `// TODO` / `// FIXME` / `// HACK` — unfinished work
  - `catch { }` or `catch _ { }` — silent error swallowing
  - `{ }` empty closures on Button actions — dead buttons
  - `as!` force casts — crash risks
  - Multiple `.sheet()` on same view — SwiftUI bug source
  - `Text("TODO")` / `Text("Placeholder")` — stub UI

### Scanner 4: SQL Integrity
- **Input:** All raw SQL strings in service files
- **Output:** List of column references that don't exist in schema
- **Method:** Extract column names from SQL → compare against migration definitions in `AppDatabase+Migrations.swift`
- **Pass condition:** Every referenced column exists in schema

### Scanner 5: Problems Folder
- **Input:** `docs/Problomes/` directory
- **Output:** List of user-reported issues not yet fixed
- **Pass condition:** Every file has been addressed

### Scanner 6: Master Issue List
- **Input:** `docs/plans/master-issue-list.md`
- **Output:** Count of open T1/T2/T3 issues
- **Pass condition:** Zero open T1, zero open T2

### Scanner 7: Plan Alignment
- **Input:** `docs/plans/` feature specs vs actual code in `Features/`
- **Output:** List of features described in plans but missing/broken in code
- **Pass condition:** Every planned feature has working implementation

### Scanner 8: Usability Patterns
- **Input:** All `.swift` files in `Weird Parts IOS/`
- **Output:** List of behavioral usability violations by category
- **Skill:** `xcode-ai/skills/usability-hunter/SKILL.md`
- **Scans for:**
  - `dismiss()` after `await` in same function — stale dismiss reference
  - `try?` on save/delete/create without error feedback — silent failures
  - `guard let service = appCore.xxxService else { return }` without error state — silent bail
  - `.sheet()` on forms with `@State` mutations but no `interactiveDismissDisabled` — accidental swipe-dismiss
  - Save/create functions with no success feedback (no toast/alert/checkmark)
  - Delete operations without `confirmationDialog` — accidental data loss
  - Async functions called without `await` — unawaited saves
- **Pass condition:** Zero CRITICAL or HIGH violations
- **GitHub label:** `usability-hunter`

---

## The Fixer (What Happens To Each Issue)

When the scanners produce a list, the fixer picks the **top 5 by priority** and processes them:

### Priority Order (highest first)
1. Compile errors (nothing works without this)
2. Test failures (existing quality is regressing)
3. SQL column mismatches (silent data corruption)
4. Problems folder items (user-reported)
5. Master issue list T1 (show-stoppers)
5.5. **Usability patterns — dismiss bugs, silent failures, missing feedback** (CRITICAL behavioral bugs, GitHub `usability-hunter` label)
6. Silent error handling (hidden failures)
7. Master issue list T2 (high priority)
8. Code pattern issues (TODOs, dead buttons, etc.)
9. Master issue list T3 (medium priority)
10. Plan alignment gaps (features not matching spec)

### Fix Protocol
For each issue:
1. **Read** the relevant source file(s)
2. **Understand** the root cause (not just the symptom)
3. **Fix** in the actual source file
4. **Add/update test** to cover the fix
5. **Build** to confirm no compile errors
6. **Run tests** to confirm no regressions
7. **Mark** the issue as fixed in the tracker

### Fix Rules
- Follow existing code patterns — don't introduce new abstractions
- Every fix gets a test (or modifies an existing test)
- If a service SQL fix is made, verify against `AppDatabase+Migrations.swift`
- If a UI fix is made, follow the `Theme/` system
- Never fix a symptom when you can fix the root cause
- If a fix would break 3+ other things, flag it for review instead

---

## The Verifier (Final Gate)

When all scanners return zero issues, run the **final verification** — a stricter, slower check:

### Final Verify Steps (ALL must pass simultaneously)
```
swift build           → 0 errors, 0 warnings
swift test            → ALL tests pass (N/N)
grep TODO/FIXME       → 0 untracked items
grep empty catches    → 0 silent swallows
grep empty closures   → 0 dead buttons
SQL column audit      → 0 mismatches
Problems folder       → 0 open items
Master issues T1      → 0 open
Master issues T2      → 0 open
Plan alignment        → all 14 modules verified
Usability patterns    → 0 critical/high violations (Scanner 8)
```

If ANY single check fails → the loop continues (back to SCAN).
If ALL pass → **DONE**

---

## Tracking

Each loop iteration updates `docs/hunt-fix-tracker.md`:

```
LOOP STATUS — Iteration N
  Scanner 1 (Compile):     pass/fail  (N errors, M warnings)
  Scanner 2 (Tests):       pass/fail  (N/M passing)
  Scanner 3 (Code):        pass/fail  (N issues)
  Scanner 4 (SQL):         pass/fail  (N mismatches)
  Scanner 5 (Problems):    pass/fail  (N open)
  Scanner 6 (Issues):      pass/fail  (T1:N T2:M T3:K)
  Scanner 7 (Plans):       pass/fail  (N gaps)
  Scanner 8 (Usability):   pass/fail  (N critical, M high)
  TOTAL OPEN:              N
  FIXED THIS ITERATION:    M
  TESTS ADDED:             K
  STATUS: CONTINUE / FINAL VERIFY / DONE
```

---

## Critical Files

### Plans (Source of Truth)
- `docs/plans/master-issue-list.md` — 65 known issues with tiers
- `docs/Problomes/` — user-reported problems (32 screenshots)
- `docs/plans/ios-page-review-tracker.md` — page review status
- `docs/RELEASE-READINESS-CHECKLIST.md` — release gates
- All `docs/plans/ios-*.md` — per-module feature specs

### Bug-hunt/Fisher Entrypoint
- Script: `scripts/bug-hunt-fisher.sh`
- Canonical plan paths:
  - `docs/plans/hunt-fix-verify-loop.md` (core plan)
  - `docs/plans/master-issue-list.md` (fishing plan)
  - `docs/hunt-fix-tracker.md` (daily run template)
- Issue selection order: `blocked` → `todo` → `backlog`
- Smoke check: `scripts/bug-hunt-fisher.sh --smoke-check` (fails fast if any required plan file is missing)

### Code (What Gets Fixed)
- `core/Sources/WiredPartCore/Services/*.swift` — 21 services
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — schema
- `core/Sources/WiredPartCore/Models/*.swift` — data models
- `Weird Parts IOS/Weird Parts IOS/Features/**/*.swift` — 14 modules, ~310 files

### Tests (What Proves It Works)
- `core/Tests/WiredPartCoreTests/*.swift` — 41 test files, 548+ tests
- Test command: `cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift test`
- Build command: `cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift build`

---

## Key Principle

The loop doesn't need to understand the app to work. It just needs:
1. Scanners that find problems mechanically
2. A priority system to pick what to fix first
3. A test suite that proves fixes work
4. A verification gate that won't let anything through until everything passes

The loop runs until the verification gate is 100% green. Repeat until clean.
