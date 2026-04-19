# PE-044 — Dismiss Guard: IOSEmployeesPage (New/Edit Employee Sheet)

> **Campaign:** #143 Dismiss Safety — Phase 1A (People/HR, highest priority).
> **Plan:** `docs/plans/dismiss-safety-campaign.md`
> **GitHub Issue:** #143 (also #123)
> **Canonical template for:** all remaining Phase 1A–1D dismiss-guard prompts.
> **Target file:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift`

---

## 1. Page Overview

`IOSEmployeesPage.swift` is the master People → Employees page. It holds the list of all employees for the shop and presents a sheet for creating a new employee and another for editing an existing one. The sheet contains a long form with personal info, contact info, hire date, hat assignments, and wage fields. Managers and owners use this page whenever a new hire is onboarded or an employee's details change — a few times a week under normal operations, but many times in a row during a bulk onboarding (seasonal hires, new contract wins).

The data entered here is high-value: employee records feed payroll, scheduling, dispatch, certifications, and permissions. Losing mid-entry data forces the manager to re-collect info from the employee — which may not be possible if the paperwork is physically offsite.

---

## 2. Current Broken Behavior

The new/edit employee sheet presented from `IOSEmployeesPage` does NOT use `.interactiveDismissDisabled()` anywhere. iOS's default behavior on sheets is: a swipe-down gesture dismisses the sheet unconditionally, even when the form has unsaved input. The user gets no warning, no confirmation, no recovery — their typed data is silently thrown away.

Code-grounded scan (2026-04-14) confirms:
- No `isDirty`, `hasUnsavedChanges`, or equivalent state in the sheet.
- No `.interactiveDismissDisabled(_:)` modifier attached to the sheet's content.
- No "Discard changes?" alert flow.
- The only state related to save behavior is `isSaving` (loading indicator).

This matches the systemic pattern across ~30+ sheets in the app, called out in GitHub #143 and #123.

---

## 3. Goal of the Change

**Primary goal:** Protect the user from accidental data loss. A swipe-down on a touched form should not silently destroy what they typed.

**Secondary goal — pattern-setting:** This is the first prompt in the #143 campaign (Phase 1A, People/HR first per owner decision). The exact code shape landed here becomes the canonical pattern for the remaining ~30 prompts across Chat, Orders, Fleet, Scheduling, Parts, Tools, and Settings. Getting the pattern clean here matters — every follow-up prompt will reference this one.

**Explicit non-goals (do not do in this prompt):**
- Do NOT change save logic, validation, or layout.
- Do NOT add `.scrollDismissesKeyboard(.interactively)` (that's the #149 campaign, separate phase).
- Do NOT add "Save & Exit" or "Save as Draft" (separate issue #148).
- Do NOT change any other sheet in this file beyond new/edit employee.
- Do NOT refactor to extract the dirty-tracking into a shared view modifier yet — let 3–5 sheets accrue the pattern first so the abstraction falls out naturally. We'll unify later.

---

## 4. Exact Code Change

### 4.1 State to add to the sheet view

Inside the struct that presents the new-employee / edit-employee form (in `IOSEmployeesPage.swift`), add these `@State` properties at the top of the struct:

```swift
@State private var isDirty: Bool = false
@State private var showDiscardAlert: Bool = false
@Environment(\.dismiss) private var dismiss   // add if not already present
```

### 4.2 `.onChange(of:)` on every bound field

For EVERY `TextField`, `Picker`, `Toggle`, `DatePicker`, `Stepper`, `Slider`, and any other user-input control inside the form, attach `.onChange(of: $value) { _, _ in isDirty = true }`. Example:

```swift
TextField("First Name", text: $firstName)
    .onChange(of: firstName) { _, _ in isDirty = true }

TextField("Last Name", text: $lastName)
    .onChange(of: lastName) { _, _ in isDirty = true }

Picker("Hat", selection: $selectedHatId) { /* ... */ }
    .onChange(of: selectedHatId) { _, _ in isDirty = true }

DatePicker("Hire Date", selection: $hireDate, displayedComponents: .date)
    .onChange(of: hireDate) { _, _ in isDirty = true }

Toggle("Active", isOn: $isActive)
    .onChange(of: isActive) { _, _ in isDirty = true }
```

**Important:** do NOT use a single `.onChange` on some parent container and try to diff all state — list each field explicitly. That makes it easy for future edits to see which fields are tracked.

### 4.3 Toolbar Cancel button

Update the Cancel toolbar button (create one if not present) to consult `isDirty`:

```swift
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") {
        if isDirty {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }
}
```

### 4.4 Discard-changes alert

Attach a confirmation alert bound to `showDiscardAlert`:

```swift
.alert("Discard changes?", isPresented: $showDiscardAlert) {
    Button("Discard", role: .destructive) {
        dismiss()
    }
    Button("Keep Editing", role: .cancel) {}
} message: {
    Text("Your unsaved changes will be lost.")
}
```

### 4.5 Interactive dismiss guard

On the outermost view of the sheet's body (typically the `NavigationStack` wrapping the form):

```swift
NavigationStack {
    Form {
        // ... sections with fields that use .onChange to set isDirty ...
    }
    .navigationTitle(isEditing ? "Edit Employee" : "New Employee")
    .toolbar { /* Cancel + Save as above */ }
    .alert("Discard changes?", isPresented: $showDiscardAlert) { /* ... */ }
}
.interactiveDismissDisabled(isDirty)     // ← THIS LINE is the key
```

### 4.6 Save-button behavior stays unchanged

The Save button's existing logic is untouched. Because the save path calls `dismiss()` programmatically (not via swipe-down), `.interactiveDismissDisabled(isDirty)` doesn't block it.

---

## 5. Acceptance Criteria

Before marking this prompt done, verify each of:

- [ ] Open the new-employee sheet, don't touch anything, swipe down → sheet dismisses cleanly (no alert, no block).
- [ ] Open the sheet, type in ONE field, swipe down → swipe is blocked, sheet stays up, no alert (iOS suppresses the gesture).
- [ ] Open the sheet, type in one field, tap Cancel → "Discard changes?" alert appears.
- [ ] From the alert, tap Discard → sheet dismisses, typed data NOT saved.
- [ ] From the alert, tap Keep Editing → alert dismisses, sheet stays up, field content preserved.
- [ ] Open the sheet, type in one field, tap Save → existing save logic runs, sheet dismisses (via programmatic `dismiss()`), employee record saved.
- [ ] Open edit-employee for existing record, don't change anything, tap Cancel → dismisses immediately (no alert — nothing was dirty).
- [ ] Open edit-employee, change one field, tap Cancel → alert appears, Discard/Keep Editing both work.
- [ ] Repeat above for `IOSEmployeeDetailPage.swift` if it presents its own edit sheet (check during implementation — may be a follow-up prompt).

---

## 6. After This Prompt Lands

- Update `xcode-ai/fix-prompts/00-fix-order.md` to mark PE-044 as complete and set PE-045 as the next (NewCertificationSheet, also in People/HR).
- Commit message: `[#143] Dismiss guard: IOSEmployeesPage new/edit employee sheet`.
- Reference the pattern established here in subsequent PE-NNN-dismiss-guard-*.md prompts — they can say "same pattern as PE-044" and only spell out file-specific field names.
- File a new issue if the employee edit sheet is presented from BOTH `IOSEmployeesPage` AND `IOSEmployeeDetailPage` with separate code — each entry point needs the guard.

---

## 7. Cross-References

- `docs/plans/dismiss-safety-campaign.md` — campaign design, scope, Phase 1A–1D ordering.
- `docs/dev-qa.md` Processed / Closed Q&A (2026-04-14) — owner decisions on priority (Q7), module order (Q8), approach (Q9), method (Q10), separation from #149 (Q11).
- GitHub `#143`, `#123` — tracking issues.
