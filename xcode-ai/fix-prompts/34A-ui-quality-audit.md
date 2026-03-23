# 34A — UI Quality Audit: Popups, Buttons, Links, Data Display

> **Chain position:** **34A** (standalone — run AFTER 32A-33H)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. Every sheet/popup MUST have a working Done/Cancel/Close button that calls `dismiss()`
2. Every `@Environment(\.dismiss) private var dismiss` must be used in at least one button
3. Every NavigationLink must have a valid destination
4. Every List row with data must show actual values, not placeholders
5. Every button must have a visible tap response (buttonStyle or tint)
6. Every `.alert` must have at least one dismiss action

## Instructions

Go through EVERY Swift file in `Weird Parts IOS/Weird Parts IOS/Features/` and check:

### 1. Sheet Dismiss Issues
For every `.sheet` presentation, verify:
- The presented view has `@Environment(\.dismiss) private var dismiss`
- There's a toolbar button (Done/Cancel/Close) that calls `dismiss()`
- The button is in `.cancellationAction` or `.confirmationAction` placement
- If the sheet has a form, the Save button dismisses after saving
- If using `NavigationStack` inside the sheet, the dismiss button is inside the NavigationStack's toolbar

**Common AI mistake:** Putting the dismiss button OUTSIDE the NavigationStack, making it invisible.

### 2. Sticky Buttons
Check for buttons that:
- Don't have any action (empty closure `{ }`)
- Have actions that never complete (stuck in loading state)
- Set `isLoading = true` but never set it back to `false` on error
- Are disabled but never re-enabled

### 3. Navigation Links
Verify every `NavigationLink` or `Button` that navigates:
- Has a valid destination view
- Passes required parameters (IDs, data)
- Doesn't navigate to stub/placeholder text

### 4. Data Display
Check that:
- Currency values use `String(format: "$%.2f", value)` not raw Double display
- Dates are formatted (not raw ISO strings like "2026-03-20T14:30:00")
- Empty states show EmptyStateView, not blank space
- Loading states show ProgressView, not frozen content
- Counts show actual numbers, not hardcoded "0"
- Optional values use `if let` or nil coalescing, not force unwrap display

### 5. Alert/Confirmation Issues
- Every destructive action (delete, cancel, remove) has a confirmation
- Alerts have proper title + message + at least 2 buttons (action + cancel)
- Cancel button has `role: .cancel`
- Destructive button has `role: .destructive`

### 6. Form Validation
- Required fields checked before save
- Error messages shown inline or via alert
- Save button disabled while saving (`isSaving` state)
- Progress indicator during save

For EVERY issue found, fix it inline. Don't just report — FIX.

## Success Criteria

- [ ] Every sheet has a working dismiss button
- [ ] No sticky/dead buttons anywhere
- [ ] All NavigationLinks go to valid destinations
- [ ] All data displays formatted properly (currency, dates, counts)
- [ ] All destructive actions have confirmations
- [ ] All forms validate before save
- [ ] Project builds with no errors
