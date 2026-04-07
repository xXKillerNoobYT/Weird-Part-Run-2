# Plan: Full-Program Usability Hunt + Usability Hunter Skill

## Context

The iOS app (87+ pages, 170+ Swift files) has a systemic usability problem: things don't work from the user's perspective even when code compiles and tests pass. Dismiss bugs (#96-#111) are already being fixed, but there are **many more undiscovered usability issues** across the full program. Existing scanners catch code-level bugs (compile errors, test failures, SQL mismatches) but miss behavioral/UX issues like: sheets that won't close, buttons that do nothing, saves that silently fail, forms you can't exit, missing feedback, and broken navigation flows.

**Goal:**
1. Hunt down ALL usability issues across the entire iOS app
2. File every one as a GitHub issue so nothing gets lost
3. Create a specialized "Usability Hunter" skill that catches these patterns automatically going forward

---

## Part 1: Full-Program Usability Sweep

### What We're Hunting (6 Categories)

**Cat 1: Dismiss & Sheet Bugs** (already found 34 files with patterns)
- `dismiss()` after `await` — stale environment reference
- `dismiss()` after `onSave()` callback that rebuilds parent
- Sheets missing `interactiveDismissDisabled` when they have unsaved data (only 7 of 170+ pages have this)
- Alert buttons calling `dismiss()` inside async closures
- Sheets with no Cancel/Close button at all

**Cat 2: Silent Failures** (197 `try?` instances across 70 files)
- `try?` that swallows errors with zero user feedback
- `guard let service = appCore.xxxService else { return }` — silent bail (~130 instances)
- Empty catch blocks (`catch { }`)
- Async functions called without `await`

**Cat 3: Missing User Feedback**
- Save/create/update completes but no toast/alert/checkmark shown
- Delete without confirmation dialog
- Long operations with no loading spinner
- Error variables that get set but never displayed in the view

**Cat 4: Navigation & Exit Traps**
- Wizards with no "Save & Exit"
- Back button that discards work without warning
- NavigationLinks inside wizards that leave the flow
- Dead-end pages with no way back

**Cat 5: Form & Input Issues**
- Save button enabled when form is invalid
- No validation before submit
- Text fields with no keyboard dismiss
- Numeric inputs accepting letters

**Cat 6: Accessibility & Touch**
- Tap targets under 44x44px
- Color-only status indicators
- Icon buttons without accessibility labels

### Already-Found Bugs to File (from exploration)

These are NEW — not duplicates of #96-#111:

| # | File | Bug | Severity |
|---|------|-----|----------|
| 1 | `QRScanSheet.swift:306,312` | `onResult()` then `dismiss()` — stale after parent rebuild | CRITICAL |
| 2 | `CascadePriceEditSheet.swift:300,319,338,366` | `await onSave()` + `loadData()` but never dismisses | CRITICAL |
| 3 | `PartsBrandsPage.swift:393-394` | `await onSave()` then `dismiss()` — classic stale pattern | CRITICAL |
| 4 | `IOSTeamDetailPage.swift:288` | dismiss after async delete | HIGH |
| 5 | `PartsFlowWizard.swift` | Sync saves, no validation, no feedback, auto-dismiss before save confirms | CRITICAL |
| 6 | `WarehouseOnboardingWizard.swift:382-395` | `saveAndExit()` doesn't await, `try?` swallows, dismiss before save | CRITICAL |
| 7 | `CompanySetupWizard.swift` | UserDefaults-only persist, nav leaves wizard mid-flow, no feedback | HIGH |
| 8 | `IOSMovementWizard.swift` | Cancel not disabled during execute, no qty validation | MODERATE |
| 9 | `IOSWarehouseSettingsPage.swift` | No `interactiveDismissDisabled(isSaving)` | MODERATE |
| 10 | **SYSTEMIC** | 197 `try?` across 70 files with no error feedback | HIGH |
| 11 | **SYSTEMIC** | 34 files with dismiss-after-await pattern | HIGH |
| 12 | **SYSTEMIC** | Only 7/170+ pages use `interactiveDismissDisabled` | MODERATE |

Plus: the full sweep will find MORE that the exploration agents didn't catch (they only sampled — the skill needs to scan ALL 170+ files).

### Execution Steps

1. **Create GitHub label** `usability-hunter` (color: `FF6B6B`)
2. **Scan ALL 323 Swift files** using grep/regex for each of the 6 categories
3. **For each finding:** check if it duplicates an existing issue (#96-#111), if not → file new issue
4. **Group systemic issues** (e.g., one issue for "all `try?` without feedback" with a checklist of files)
5. **Label all issues** with `usability-hunter` + `bug` or `enhancement`
6. **Update `docs/usability-tracker.md`** with findings

### Files to Scan
- All files in `Weird Parts IOS/Weird Parts IOS/` (323 .swift files)
- Focus areas: `Features/` (all modules), `Auth/`, `Scanning/`, `Shared/`, `Navigation/`

---

## Part 2: Create the Usability Hunter Skill

### File: `xcode-ai/skills/usability-hunter/SKILL.md`

A new specialized skill with **6 scanners** (one per category above). Key differences from the existing usability-enforcer:

| Aspect | Usability Enforcer (existing) | Usability Hunter (new) |
|--------|-------------------------------|------------------------|
| Focus | Structural (page loads, error states, sheet modifiers) | Behavioral (does it WORK from the user's POV?) |
| Method | Checks for presence of patterns | Checks for ABSENCE of safety patterns |
| Output | Fixes inline | Files GitHub issues |
| Schedule | 2 PM daily | 10 AM daily (runs first, finds issues for enforcer to verify) |

### Scanner Definitions (with grep patterns)

**Scanner 1: Dismiss Safety**
```bash
# Find dismiss-after-await (multiline)
grep -rlZ "await.*\n.*dismiss()" Weird\ Parts\ IOS/
# Find sheets missing interactiveDismissDisabled
# (files with .sheet AND @State but no interactiveDismissDisabled)
```

**Scanner 2: Silent Failures**
```bash
# try? without error feedback within 5 lines
grep -n "try?" Weird\ Parts\ IOS/ --include="*.swift"
# guard-let-service-return
grep -n "guard let.*Service.*else.*return" Weird\ Parts\ IOS/ --include="*.swift"
# empty catches
grep -n "catch {" Weird\ Parts\ IOS/ --include="*.swift"
```

**Scanner 3: Missing Feedback** — check save/delete functions for toast/alert/success variables

**Scanner 4: Navigation Traps** — check wizards for exit paths, forms for dirty tracking

**Scanner 5: Form Issues** — check Button+save for .disabled, TextField for keyboard dismiss

**Scanner 6: Accessibility** — check frame sizes, color-only indicators, missing labels

### Fix Protocol
- **CRITICAL** (dismiss bugs, data loss, silent saves): Fix immediately in Swift, test, commit
- **HIGH** (missing feedback, validation gaps): Fix if < 30 min, otherwise file issue
- **MODERATE** (accessibility, keyboard, polish): File GitHub issue with label
- Max 10 fixes per run, always file issues for what can't be fixed this run

### Suppression
- `// usability-hunter: acceptable` inline comment suppresses a specific finding
- Prevents false positives on intentional `try?` (e.g., optional cache reads)

---

## Part 3: Update Existing Infrastructure

### A. Hunt-Fix-Verify Loop (`docs/plans/hunt-fix-verify-loop.md`)
- Add **Scanner 8: Usability Patterns** after Scanner 7 (Plan Alignment)
- Scans for: dismiss-after-await, `try?` without feedback, missing `interactiveDismissDisabled`, unawaited async saves
- Pass condition: Zero CRITICAL or HIGH violations
- Add to priority order at position 5.5 (after user-reported, before T1 issues)
- Add to Final Verify gate

### B. Usability Enforcer Skill (`xcode-ai/skills/usability-enforcer/SKILL.md`)
- Add items 15-20 to Scanner 7 (Defensive UX Patterns):
  - 15: Dismiss-after-await
  - 16: Silent `try?`
  - 17: Unawaited saves
  - 18: Missing `interactiveDismissDisabled`
  - 19: Save without feedback
  - 20: Delete without confirmation
- Add "Integration with Usability Hunter" section explaining their complementary roles

### C. Usability Tracker (`docs/usability-tracker.md`)
- Add "Usability Hunter Results" section with scanner results table
- Add "GitHub Issues Filed" tracking table

### D. Create Scheduled Task
- taskId: `usability-hunter`
- Schedule: `0 10 * * *` (10 AM daily)
- Pipeline order: hunt-fix (6AM) → **usability-hunter (10AM)** → usability-enforcer (2PM) → page-rebuild (4PM)

---

## Part 4: Verification

1. **Skill file exists** at `xcode-ai/skills/usability-hunter/SKILL.md` with all 6 scanners
2. **GitHub issues filed** — at minimum the 12 known bugs, plus whatever the full sweep finds
3. **Scheduled task created** and running
4. **Hunt-fix loop updated** with Scanner 8
5. **Usability enforcer updated** with new pattern checks
6. **First manual run** — execute the skill once to populate initial findings and verify it catches the known bugs

### Test the Skill
- Run Scanner 1 grep patterns → should find the 34 dismiss-after-await files
- Run Scanner 2 grep patterns → should find the 197 `try?` instances
- Cross-check against known bugs → all 12 should be detected
- Verify no false positives on already-fixed issues (#96-#111)

---

## Critical Files

| File | Action |
|------|--------|
| `xcode-ai/skills/usability-hunter/SKILL.md` | CREATE — new skill |
| `xcode-ai/skills/usability-enforcer/SKILL.md` | EDIT — add patterns 15-20, integration section |
| `docs/plans/hunt-fix-verify-loop.md` | EDIT — add Scanner 8 |
| `docs/usability-tracker.md` | EDIT — add hunter results section |
| All 323 `.swift` files in `Weird Parts IOS/` | SCAN (read-only) |
| GitHub repo | CREATE issues with `usability-hunter` label |
