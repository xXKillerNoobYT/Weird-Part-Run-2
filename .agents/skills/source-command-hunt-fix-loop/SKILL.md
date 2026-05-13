---
name: "source-command-hunt-fix-loop"
description: "Autonomous hunt-fix-verify loop. Scans for ALL problems (compile, test, code patterns, SQL, user-reported, plan alignment), fixes top priorities, tests, verifies, and repeats until 100% clean. Use /hunt-fix-loop to run one iteration."
---

# source-command-hunt-fix-loop

Use this skill when the user asks to run the migrated source command `hunt-fix-loop`.

## Command Template

# Hunt-Fix-Verify Loop — Iteration Runner

You are executing ONE iteration of the autonomous hunt-fix-verify loop. Follow these steps exactly. Do NOT skip steps. Do NOT stop early.

---

## STEP 1: SCAN (Run All Scanners)

Run ALL of these scans. Collect every issue into a single list.

### Scanner 1: Compile
```bash
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift build 2>&1 | grep -E "error:|warning:" | head -50
```
**Pass:** Zero errors AND zero warnings.

### Scanner 2: Tests
```bash
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift test 2>&1 | tail -5
```
**Pass:** ALL tests pass (the "Test run with N tests in M suites passed" line).

### Scanner 3: Code Patterns
Run these greps on `core/Sources/` and `Weird Parts IOS/`:
```bash
# TODOs and FIXMEs
grep -rn "// TODO\|// FIXME\|// HACK\|// BUG" core/Sources/ "Weird Parts IOS/" --include="*.swift" 2>/dev/null

# Empty catch blocks (silent error swallowing)
grep -rn "catch {" core/Sources/ --include="*.swift" | grep -v "catch {$" | head -30
grep -rn "catch { }" core/Sources/ --include="*.swift" | head -30

# Force casts
grep -rn " as! " core/Sources/ --include="*.swift" | head -20

# Multiple .sheet() on same file (SwiftUI bug source)
for f in $(find "Weird Parts IOS/" -name "*.swift"); do count=$(grep -c "\.sheet(" "$f" 2>/dev/null); if [ "$count" -gt "1" ]; then echo "$f: $count sheets"; fi; done
```
**Pass:** Zero untracked TODOs. Zero empty catches. Zero force casts. Zero multi-sheet files.

### Scanner 4: SQL Integrity
For every service file in `core/Sources/WiredPartCore/Services/*.swift`:
- Read the file
- Find every raw SQL string (anything in triple-quotes or string interpolation with SQL keywords)
- Extract column names referenced
- Cross-reference against `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- Flag any column that doesn't exist in the schema

**Pass:** Every referenced column exists in the actual schema.

### Scanner 5: Problems Folder
```bash
ls -la "/Users/IA/GitHub/Weird-Part-Run-2/docs/Problomes /" 2>/dev/null
```
Read every file (including screenshots). For screenshots, use the Read tool to view them.
**Pass:** Every problem has been addressed.

### Scanner 6: Master Issue List
```bash
cat /Users/IA/GitHub/Weird-Part-Run-2/docs/plans/master-issue-list.md
```
Count open T1 (show-stoppers), T2 (high), and T3 (medium) issues.
**Pass:** Zero open T1, zero open T2.

### Scanner 7: Plan Alignment
For each feature module in `Weird Parts IOS/Weird Parts IOS/Features/`:
- Read the corresponding plan in `docs/plans/ios-*-pages.md`
- Check if planned features actually exist in code
- Flag any gaps

**Pass:** Every planned feature has working implementation.

### Scanner 8: GitHub Issues
```bash
gh issue list --repo xXKillerNoobYT/Weird-Part-Run-2 --state open --limit 50
```
- Count total open issues
- Classify each as: SERVICE_FIX, UI_FIX, CROSS_CUTTING, NEW_FEATURE, DB_MIGRATION, XCODE_ONLY
- Count auto-fixable (SERVICE_FIX + UI_FIX + CROSS_CUTTING + DB_MIGRATION)
- Count needs-xcode (XCODE_ONLY)
- Identify T1 show-stoppers (crashes, data loss, can't clock in)

**Pass:** Zero open T1 issues. Zero auto-fixable SERVICE_FIX issues.

---

## STEP 2: TRIAGE

After all scans complete, produce this status board:

```
══════════════════════════════════
  LOOP STATUS — Iteration N
══════════════════════════════════
  Scanner 1 (Compile):     ✅/❌  (N errors, M warnings)
  Scanner 2 (Tests):       ✅/❌  (N/M passing)
  Scanner 3 (Code):        ✅/❌  (N issues)
  Scanner 4 (SQL):         ✅/❌  (N mismatches)
  Scanner 5 (Problems):    ✅/❌  (N open)
  Scanner 6 (Issues):      ✅/❌  (T1:N T2:M T3:K)
  Scanner 7 (Plans):       ✅/❌  (N gaps)
  Scanner 8 (GitHub):      ✅/❌  (N open, M auto-fixable)
  ─────────────────────────────
  TOTAL OPEN:              N
  STATUS: CONTINUE / FINAL VERIFY / DONE
══════════════════════════════════
```

If TOTAL OPEN = 0, skip to STEP 5 (FINAL VERIFY).

---

## STEP 3: FIX (Top 5 by priority)

Pick the **top 5 issues** using this priority:
1. Compile errors
2. Test failures
3. SQL column mismatches
4. GitHub T1 issues (show-stoppers from Scanner 8)
5. Problems folder items (user-reported)
6. Master issue T1 (show-stoppers)
7. Silent error handling
8. Master issue T2 (high priority)
9. Code patterns (TODOs, dead buttons, etc.)
10. GitHub auto-fixable issues (SERVICE_FIX, UI_FIX from Scanner 8)
11. Master issue T3 (medium)
12. Plan alignment gaps

For EACH issue:
1. **Read the plan** — check `docs/plans/` for the relevant feature BEFORE coding
2. **Read the schema** — `AppDatabase+Migrations.swift` for ANY SQL-related fix
3. **Read** the source file
4. **Understand** root cause (not symptom)
5. **Fix** in actual source file using Edit tool
6. **Add test** or update existing test to cover the fix
7. **Build check** — `swift build` must succeed after EACH fix
8. **Test check** — `swift test` must pass ALL tests after EACH fix
9. **Update GitHub** — if the fix resolves a GitHub issue, comment on it:
   ```bash
   gh issue comment $ISSUE_NUMBER --repo xXKillerNoobYT/Weird-Part-Run-2 --body "Fixed in hunt-fix-loop iteration N. Files changed: [list]. Tests: ✅"
   ```
10. **Close issue** — if fully resolved:
    ```bash
    gh issue close $ISSUE_NUMBER --repo xXKillerNoobYT/Weird-Part-Run-2 --comment "Resolved — all checks pass."
    ```

### Fix Rules
- **Read plan before EVERY fix** — no coding without context
- Follow existing code patterns
- Every fix gets a test
- SQL fixes verified against AppDatabase+Migrations.swift — EVERY TIME
- UI fixes follow existing patterns in the same file
- Fix root cause, not symptom
- Never hardcode user ID `1` — always flow from session
- No `import GRDB` in UI files — service layer only
- `isTableNotFoundError` on all service catch blocks
- If fix would break 3+ other things, flag for user review
- Max 3 consecutive failures on same issue → skip it, comment "Needs manual review"

---

## STEP 4: VERIFY BATCH

After fixing the batch:
```bash
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift build 2>&1 | tail -3
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift test 2>&1 | tail -5
```

Both must pass. If either fails, fix the regression before proceeding.

Update `docs/hunt-fix-tracker.md` with:
- What was found
- What was fixed
- What tests were added
- Current open count

Then say: **"Iteration N complete. M issues fixed. K remaining. Run /hunt-fix-loop for next iteration."**

---

## STEP 5: FINAL VERIFY (Only when TOTAL OPEN = 0)

Run ALL of these. ALL must pass simultaneously:

```bash
# Build clean
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift build 2>&1 | grep -c "warning:"
# → Must be 0

# All tests pass
cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift test 2>&1 | tail -3
# → "Test run with N tests in M suites passed"

# Zero TODOs
grep -rn "// TODO\|// FIXME\|// HACK\|// BUG" /Users/IA/GitHub/Weird-Part-Run-2/core/Sources/ --include="*.swift" | wc -l
# → Must be 0

# Zero empty catches in services
grep -rn "catch { }" /Users/IA/GitHub/Weird-Part-Run-2/core/Sources/WiredPartCore/Services/ --include="*.swift" | wc -l
# → Must be 0

# Problems folder
ls "/Users/IA/GitHub/Weird-Part-Run-2/docs/Problomes /" 2>/dev/null | wc -l
# → 0 unaddressed items

# Master issues
grep -c "T1-.*open\|T1-.*❌" /Users/IA/GitHub/Weird-Part-Run-2/docs/plans/master-issue-list.md 2>/dev/null
# → Must be 0
```

If ALL pass: **"✅ LOOP COMPLETE. All scanners green. All tests pass. All issues resolved."**
If ANY fail: **Go back to STEP 1.**

---

## Key Files

### Plans (Source of Truth)
- `docs/plans/master-issue-list.md` — 65 known issues
- `docs/Problomes /` — user-reported problems (screenshots)
- `docs/plans/ios-page-review-tracker.md` — page review status
- `docs/RELEASE-READINESS-CHECKLIST.md` — release gates

### Code
- `core/Sources/WiredPartCore/Services/*.swift` — 21 services
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — schema truth
- `Weird Parts IOS/Weird Parts IOS/Features/` — 14 modules

### Tests
- `core/Tests/WiredPartCoreTests/*.swift` — 41 test files
- `core/Tests/WiredPartCoreTests/E2ETestHelpers.swift` — test setup
