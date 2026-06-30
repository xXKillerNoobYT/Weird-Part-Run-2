# Usability Hunter Agent

> **Schedule:** Daily at 10:00 AM
> **Priority:** CRITICAL
> **Tracker:** `docs/usability-tracker.md`
> **GitHub Label:** `usability-hunter`

---

## Purpose

Hunt for **behavioral usability bugs** that make the app feel broken to users — even when code compiles and tests pass. This agent scans ALL Swift files in `Weird Parts IOS/` for patterns that cause: sheets that won't close, buttons that do nothing, saves that silently fail, forms you can't exit, missing feedback, and broken navigation flows.

**Difference from Usability Enforcer:** The enforcer checks STRUCTURAL correctness (page loads, error states, sheet existence). This agent checks BEHAVIORAL correctness (does it actually WORK from the user's perspective?).

---

## 6 Scanners

### Scanner 1: Dismiss & Sheet Safety

**What it catches:** Sheets that won't close, stale dismiss references, accidental swipe-dismiss during saves.

**Scan commands:**

```bash
# 1a. dismiss() after await in same function (stale reference)
cd "Weird Parts IOS"
grep -rnl "await" --include="*.swift" | while read f; do
  # Check if same file has dismiss() — then manually verify they're in the same function
  grep -l "dismiss()" "$f" 2>/dev/null
done

# 1b. Sheets missing interactiveDismissDisabled
# Find files with .sheet AND @State mutations but no interactiveDismissDisabled
grep -rnl "\.sheet(" --include="*.swift" | while read f; do
  if grep -q "@State.*isSaving\|@State.*isEditing\|@State.*hasChanges\|TextField(" "$f"; then
    if ! grep -q "interactiveDismissDisabled" "$f"; then
      echo "MISSING interactiveDismissDisabled: $f"
    fi
  fi
done

# 1c. Sheets with no Cancel/Close/X button
grep -rnl "\.sheet(" --include="*.swift" | while read f; do
  if ! grep -q 'Cancel\|"Close"\|"Done"\|xmark\|dismiss()' "$f"; then
    echo "NO DISMISS PATH: $f"
  fi
done
```

**Known violations (baseline):**
- 90 files use `dismiss()` — cross-check each against `await` in same function
- Only 7 of 170 pages with `.sheet()` use `interactiveDismissDisabled`
- Issues #96-#111 cover some dismiss bugs — check before filing duplicates

**Severity:**
- CRITICAL: dismiss after await (sheet stuck open)
- HIGH: missing interactiveDismissDisabled on forms with saves
- MODERATE: sheets with only drag-to-dismiss (no button)

---

### Scanner 2: Silent Failure Detection

**What it catches:** Errors swallowed silently, services that fail without telling the user.

**Scan commands:**

```bash
# 2a. try? without error feedback (198 instances across 72 files)
grep -rn "try?" --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  # Check if error/toast/alert variable is set within 5 lines
  context=$(sed -n "$((linenum)),$((linenum+5))p" "$file")
  if ! echo "$context" | grep -q "error\|Error\|toast\|alert\|message\|Message"; then
    echo "SILENT try?: $line"
  fi
done

# 2b. guard-let-service-else-return (426 instances — silent bail)
grep -rn "guard let.*service.*=.*appCore.*else" --include="*.swift" "Weird Parts IOS/"

# 2c. Empty catch blocks
grep -Prn "catch\s*\{[\s]*\}" --include="*.swift" "Weird Parts IOS/"

# 2d. Async functions called without await
grep -rn "saveProgress\|saveAndExit\|finishOnboarding" --include="*.swift" "Weird Parts IOS/" | grep -v "await"
```

**Known violations (baseline):**
- 198 `try?` across 72 files
- 426 `guard let service = appCore.xxxService else { return }` instances
- Key files: `IOSClockPage.swift` (10 try?), `IOSScheduleConfigPage.swift` (11 try?), `IOSNotebookDetailPage.swift` (8 try?)

**Severity:**
- CRITICAL: try? on save/delete/create operations (data loss)
- HIGH: guard-let-service-return with no error shown
- MODERATE: try? on read/load operations (stale data)

**Suppression:** `// usability-hunter: acceptable` inline comment suppresses a finding (for intentional optional reads like cache lookups).

---

### Scanner 3: Missing User Feedback

**What it catches:** Operations that complete without any visible confirmation.

**Scan commands:**

```bash
# 3a. Save/update functions without success feedback
grep -rn "func save\|func update\|func create" --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  # Check if file has any success indicator
  if ! grep -q "toast\|showSuccess\|checkmark\|isSaved\|\"Saved\"\|\"Created\"\|\"Updated\"" "$file"; then
    echo "NO SUCCESS FEEDBACK: $line"
  fi
done

# 3b. Delete operations without confirmation
grep -rn "func delete\|\.delete\|remove(" --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  if ! grep -q "confirmationDialog\|showDeleteConfirm\|alert.*delete\|alert.*remove" "$file"; then
    echo "DELETE WITHOUT CONFIRM: $line"
  fi
done

# 3c. Async operations without loading indicator
grep -rn "Task {" --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  if ! grep -q "isLoading\|isSaving\|isProcessing\|ProgressView\|showLoading" "$file"; then
    echo "NO LOADING INDICATOR: $line"
  fi
done

# 3d. Error state variables never shown in view body
# (set in functions but not referenced in body)
grep -rn "@State.*var.*[Ee]rror" --include="*.swift" "Weird Parts IOS/"
```

**Severity:**
- HIGH: Save/create without success feedback
- HIGH: Delete without confirmation dialog
- MODERATE: Missing loading spinner on async ops
- LOW: Error variable declared but never displayed

---

### Scanner 4: Navigation & Exit Traps

**What it catches:** Users who get stuck or lose data navigating.

**Scan commands:**

```bash
# 4a. Wizards without Save & Exit
grep -rl "Wizard" --include="*.swift" "Weird Parts IOS/" | while read f; do
  if ! grep -q "Save.*Exit\|saveAndExit\|Save & Exit" "$f"; then
    echo "WIZARD WITHOUT SAVE & EXIT: $f"
  fi
done

# 4b. Forms without dirty tracking / discard confirmation
grep -rl "Form {" --include="*.swift" "Weird Parts IOS/" | while read f; do
  if grep -q "TextField\|TextEditor\|Picker\|Toggle" "$f"; then
    if ! grep -q "hasUnsavedChanges\|isDirty\|confirmDiscard\|interactiveDismissDisabled" "$f"; then
      echo "FORM WITHOUT DIRTY TRACKING: $f"
    fi
  fi
done

# 4c. NavigationLink inside wizards (leaves wizard flow)
grep -rl "Wizard" --include="*.swift" "Weird Parts IOS/" | while read f; do
  if grep -q "NavigationLink" "$f"; then
    echo "NAV LINK INSIDE WIZARD: $f"
  fi
done

# 4d. Pages presented as sheets with no back/cancel in toolbar
grep -rl "\.sheet(" --include="*.swift" "Weird Parts IOS/" | while read f; do
  if ! grep -q '\.toolbar\|ToolbarItem\|navigationBarItems' "$f"; then
    echo "SHEET WITHOUT TOOLBAR: $f"
  fi
done
```

**Severity:**
- CRITICAL: No way to exit a view (dead end)
- HIGH: Wizard without Save & Exit
- HIGH: Form without dirty tracking
- MODERATE: NavigationLink escaping wizard flow

---

### Scanner 5: Form & Input Issues

**What it catches:** Forms that accept bad data or frustrate input.

**Scan commands:**

```bash
# 5a. Save buttons without .disabled() validation
# NOTE (2026-04-06 calibration): Use ±5 lines, NOT ±2 lines.
# SwiftUI toolbar Button { … } label: { … } always places .disabled()
# 3-4 lines AFTER the Button line — ±2 produces near 100% false positives.
grep -rn 'Button.*[Ss]ave\|Button.*[Cc]reate\|Button.*[Ss]ubmit' --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  context=$(sed -n "$((linenum-2)),$((linenum+5))p" "$file")
  if ! echo "$context" | grep -q "disabled\|\.disabled"; then
    echo "SAVE WITHOUT DISABLED: $line"
  fi
done

# 5b. TextFields without keyboard dismiss
grep -rl "TextField\|TextEditor" --include="*.swift" "Weird Parts IOS/" | while read f; do
  if ! grep -q "scrollDismissesKeyboard\|toolbar.*keyboard\|\.submitLabel\|interactiveDismissDisabled" "$f"; then
    echo "NO KEYBOARD DISMISS: $f"
  fi
done

# 5c. Numeric TextField without keyboardType
grep -rn 'TextField.*[Qq]uantity\|TextField.*[Cc]ost\|TextField.*[Pp]rice\|TextField.*[Aa]mount\|TextField.*[Nn]umber' --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  if ! grep -q "keyboardType(.decimalPad)\|keyboardType(.numberPad)" "$file"; then
    echo "NUMERIC WITHOUT KEYBOARD TYPE: $line"
  fi
done
```

**Severity:**
- HIGH: Save enabled when form is invalid
- MODERATE: Missing keyboard dismiss
- LOW: Wrong keyboard type for numeric fields

---

### Scanner 6: Accessibility & Touch

**What it catches:** Unusable UI on touch devices.

**Scan commands:**

```bash
# 6a. Small tap targets (frame < 44px on interactive elements)
grep -rn "\.frame(width:" --include="*.swift" "Weird Parts IOS/" | while read line; do
  width=$(echo "$line" | grep -oP 'width:\s*\K\d+')
  if [ -n "$width" ] && [ "$width" -lt 44 ]; then
    echo "SMALL TAP TARGET ($width px): $line"
  fi
done

# 6b. Color-only status (no accompanying text/icon)
grep -rn "Color\.red\|Color\.green\|Color\.orange\|\.foregroundColor(.red)\|\.foregroundColor(.green)" --include="*.swift" "Weird Parts IOS/" | grep -i "status\|state\|priority\|badge\|indicator"

# 6c. Icon buttons without accessibility labels
grep -rn 'Image(systemName:' --include="*.swift" "Weird Parts IOS/" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  context=$(sed -n "$((linenum-1)),$((linenum+2))p" "$file")
  if echo "$context" | grep -q "Button"; then
    if ! echo "$context" | grep -q "accessibilityLabel\|Label("; then
      echo "ICON BUTTON NO A11Y: $line"
    fi
  fi
done
```

**Severity:**
- HIGH: Tap target under 44px on primary actions
- MODERATE: Color-only status indicators
- LOW: Missing accessibility labels

---

## Fix Protocol

### Priority Order
1. **CRITICAL** — Fix immediately. Dismiss bugs causing stuck sheets, data loss from silent saves, dead-end navigation. Direct Swift edit, test, commit.
2. **HIGH** — Fix if under 30 minutes. Missing feedback, validation gaps, guard-let-service-return. Otherwise update an existing GitHub issue/umbrella or file one if no tracker exists after search.
3. **MODERATE** — Update or file GitHub tracking with `usability-hunter` + `bug` labels. Include file path, line number, pattern category. Group repeated instances with the same root cause into one umbrella issue/checklist instead of one issue per file.
4. **LOW** — Update or file GitHub tracking with `usability-hunter` + `enhancement` labels; prefer umbrella/checklist tracking for repeated scanner classes.

### Per-Fix Steps
1. Read the file and understand root cause
2. Fix in Swift (for CRITICAL/HIGH that are quick)
3. Run `cd core && swift build && swift test`
4. If tests pass → commit with message: `fix(ios): [scanner-N] description`
5. Update `docs/usability-tracker.md`
6. File or update GitHub issue

### GitHub Issue Format
```
Title: [Usability] Category: Brief description
Labels: usability-hunter, bug (or enhancement)
Body:
## Scanner
Scanner N: Category Name

## File(s)
- `path/to/file.swift:LINE`

## Pattern
Description of the usability violation

## Impact
What the user experiences

## Fix
Suggested approach

## Related Issues
#NNN (if applicable)
```

### Limits
- Max **10 fixes** per run (prevent runaway changes)
- Max **20 issues filed** per run
- Always file issues for findings you can't fix this run
- **3 consecutive failures** on same file → skip, comment "Needs manual review"

---

## Suppression

Add `// usability-hunter: acceptable` on the same line or line above to suppress a finding.

Use sparingly for:
- Intentional `try?` on cache/optional reads
- Sheets that deliberately allow swipe-dismiss (e.g., info-only modals)
- Guard-let-return in init/setup where service absence is expected

**Never suppress:**
- try? on save/delete/create
- Missing dismiss paths
- Delete without confirmation

---

## Baseline Metrics (2026-04-06)

| Scanner | Metric | Count |
|---------|--------|-------|
| 1 | Files with dismiss() | 90 |
| 1 | Files with .sheet() | 170 |
| 1 | Files with interactiveDismissDisabled | 7 |
| 2 | try? instances | 198 across 72 files |
| 2 | guard-let-service-return | 426 instances |
| 3 | Delete with confirmationDialog | 25 files |
| 3 | Delete buttons total | 45+ |
| 5 | Files with TextField | ~100+ |
| 6 | Files with frame < 44px | TBD (first run) |

---

## Integration

- **Hunt-Fix-Verify Loop:** Scanner 8 (Usability Patterns) references this skill's findings
- **Usability Enforcer:** Scanner 7 items 15-20 mirror this skill's top-priority patterns
- **Page Rebuild Enforcer:** Category D (Data Integrity) and E (Feature Completeness) overlap — this skill provides the behavioral layer
- **GitHub Issues:** All findings filed with `usability-hunter` label for tracking and assignment

---

## Run Checklist

1. [ ] Pull latest code
2. [ ] Run all 6 scanners
3. [ ] Triage findings by severity (CRITICAL → HIGH → MODERATE → LOW)
4. [ ] Fix top CRITICAL items (max 10 per run)
5. [ ] Build and test: `cd core && swift build && swift test`
6. [ ] File GitHub issues for all unfixed findings
7. [ ] Update `docs/usability-tracker.md` with run results
8. [ ] Verify test count >= previous run
9. [ ] Commit fixes: `fix(ios): usability-hunter run N — [summary]`
