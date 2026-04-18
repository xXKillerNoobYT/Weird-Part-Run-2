# Dismiss Safety Campaign — #143 (Interactive Dismiss) + #149 (Scroll Keyboard Dismiss)

> **Status:** Design approved 2026-04-14, REFINED 2026-04-18. Method flipped from Xcode AI prompts → smart-patcher automation script after per-POV re-ratification. Pilot PE-044 shipped 2026-04-15.
> **GitHub Issues:** #143 (also #123) + #149
> **Pipeline item:** `PE-DISMISS` (previously "Awaiting owner answers", now unblocked)
> **Supersedes:** `docs/dev-qa.md` Q7–Q11 (now processed).
> **Release context:** Program in **development stage preparing for BETA** release — pattern quality matters because it's public-bound. See `.claude/projects/.../memory/feedback_release_state.md`.

---

## Context

~30+ form sheets across the app (Settings, People, Chat, Orders, Fleet, Scheduling, Parts, Tools) allow iOS's default swipe-down gesture to dismiss the sheet without confirmation — **all unsaved input is thrown away silently.** Repeated user reports trace to this pattern.

Additionally, ~30 scrollable pages with text fields do not use `.scrollDismissesKeyboard(.interactively)` — the keyboard stays locked up when the user scrolls away from a text field, blocking content below.

### What the codebase looks like today (pre-campaign)

Scan of representative sheets (`PricingBulkEditSheet.swift`, `PricingSettingsSheet.swift`, `PricingOverrideFlow.swift`):
- `isSaving` state is tracked (for loading spinners), but NO `isDirty` / `hasUnsavedChanges` state exists.
- NO sheet uses `.interactiveDismissDisabled(dynamicCondition)` — even where `.interactiveDismissDisabled(true)` appears, it's unconditional.
- NO scrollable page uses `.scrollDismissesKeyboard(.interactively)`.

This is genuinely net-new pattern territory. Whatever we ship first becomes the pattern every future sheet copies.

---

## Owner Decisions (from dev-qa.md Q7–Q11, 2026-04-14; REFINED 2026-04-18 per-POV)

| # | Decision |
|---|---|
| Q7 | **Do NOW but PILOT FIRST** (refined 2026-04-18). Pre-release / pre-beta posture. PE-044 (IOSEmployeesPage AddEmployeeSheet, shipped 2026-04-15 via direct edit) is the canonical pilot. Let it get real-use validation during beta prep; then scale. Don't write 30 prompts upfront. Campaign slots BEFORE page-rebuild wave. |
| Q8 | **Module order: People/HR → Chat → Orders/Fleet/Scheduling → Parts/Tools/Settings.** People/HR has the highest data-loss stakes (cert forms, wage edits, new-employee forms are long and high-value). Chat composer loss is acutely painful mid-typing. Settings rarely-entered, lowest total risk. |
| Q9 | **Per-sheet dirty tracking** (`@State var isDirty` + `.onChange` watchers + `.interactiveDismissDisabled(isDirty)` + Discard alert on Cancel). NOT blanket unconditional block — that would add false friction to untouched sheets. Pattern proven in PE-044. |
| Q10 | **Smart-patcher automation script** (FLIPPED 2026-04-18 from "Xcode AI prompts"). Python/Swift script in `execution/` per 3-layer architecture. Script reads each sheet file, detects bound inputs (TextField / Picker / Toggle / DatePicker / Stepper / Slider), injects the pattern, emits per-file review report. Human spot-checks before commit. **PE-044 becomes the reference output shape** — the script produces files shaped like PE-044. Runs only AFTER PE-044 pilot validates the pattern. |
| Q11 | **#149 is a separate, later campaign** (Phase 2). #143 ships alone first — data-loss fix takes priority. #149 keyboard dismiss is UX annoyance. Kept separate to keep the #143 smart-patcher script focused on dirty-tracking. |

---

## Design

### The canonical SwiftUI pattern (#143)

Every in-scope sheet receives this pattern:

```swift
struct SomeFormSheet: View {
    @State private var isDirty: Bool = false
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var showDiscardAlert: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .onChange(of: name) { _, _ in isDirty = true }
                TextField("Email", text: $email)
                    .onChange(of: email) { _, _ in isDirty = true }
                // … other fields with .onChange(of:) { _, _ in isDirty = true }
            }
            .navigationTitle("Edit Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)   // blocks swipe-down only when dirty
    }
}
```

### The smart-patcher script (PRIMARY delivery — refined 2026-04-18)

Lives in `execution/dismiss_guard_patcher.py` (or `.swift` if we want a SwiftPM tool for better AST support).

**Inputs:** a glob of Swift sheet files (`Weird Parts IOS/**/*Sheet.swift`, `Weird Parts IOS/**/Add*.swift`, `Weird Parts IOS/**/Edit*.swift`, etc.).

**For each file, the script:**

1. **Detects** the sheet struct and its view body.
2. **Scans for bound inputs** — any `TextField(.*text: $X)`, `Picker(.*selection: $X)`, `Toggle(.*isOn: $X)`, `DatePicker(.*selection: $X)`, `Stepper(.*value: $X)`, `Slider(.*value: $X)`. Collects the `$X` binding name for each.
3. **Injects state declarations** at the top of the struct:
   - `@State private var isDirty: Bool = false`
   - `@State private var showDiscardAlert: Bool = false`
   - `@Environment(\.dismiss) private var dismiss` (if not already present)
4. **Attaches `.onChange`** to each detected bound input: `.onChange(of: <binding>) { _, _ in isDirty = true }`
5. **Rewrites the Cancel toolbar button** (if present) to consult `isDirty`. If no Cancel button exists, adds one in `.toolbar { ToolbarItem(placement: .cancellationAction) { ... } }`.
6. **Attaches the Discard alert** to the sheet's outermost view.
7. **Adds `.interactiveDismissDisabled(isDirty)`** on the outermost view (NavigationStack / VStack).
8. **Emits a review report** per file with: detected bindings, injected lines, warnings (e.g. "sheet has a custom Cancel flow that needs manual review", "no NavigationStack found — pattern not applied").

**Output shape matches PE-044** — the canonical reference file is `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift` (AddEmployeeSheet). The script's patched output should be indistinguishable in shape from that hand-crafted pilot.

**Safety rails:**
- **Dry-run by default.** `python dismiss_guard_patcher.py --dry-run` prints the planned diff without writing. `--apply` commits. User reviews the dry-run before approving `--apply`.
- **Skip files already patched.** Script detects the pattern (e.g. `@State private var isDirty`) and skips files with it present.
- **Skip files outside scope.** Files without a sheet struct or without bound inputs are logged and skipped.
- **Human spot-check before commit.** Even on `--apply`, the script writes changes but does NOT commit. A human reviews the diff, runs `swift build`, and commits the batch.
- **Phase 1A first, batched small.** Even though the script is fast, don't patch all 30 files in one PR. Batch by Phase (1A People/HR, 1B Chat, 1C Orders/Fleet/Scheduling, 1D Parts/Tools/Settings) so each batch is reviewable.

### Pilot status

**PE-044 (IOSEmployeesPage AddEmployeeSheet)** — ✅ **SHIPPED 2026-04-15 via direct Swift edit.** This is NOT a script output — it's the hand-crafted template whose shape the script will match. Before the script runs on other sheets, PE-044 should get real-use validation (open/edit/swipe-dismiss test on device or simulator). If edge cases appear, we refine PE-044 first, then update the script's output shape to match.

### The (deprecated) Xcode AI prompt template

Kept here as reference in case individual sheets need manual treatment that the script can't handle cleanly. Every `PE-NNN-dismiss-guard-<sheet-name>.md` prompt under `xcode-ai/fix-prompts/` would contain:

```markdown
# PE-NNN — Dismiss Guard: <SheetName>.swift

## 1. Page Overview
<What the sheet is. What feature it supports. Who uses it. How often. What data it holds.>

## 2. Current Broken Behavior
Today the user can swipe down on this sheet and iOS dismisses it silently.
All unsaved input is thrown away with no warning. Scan confirms no isDirty
tracking and no interactiveDismissDisabled guard in this file.

## 3. Goal of the Change
Protect the user from accidental data loss on a sheet that commonly holds
<high-value content: certifications / wage records / composed messages / ...>.
Establish the per-sheet dirty-tracking pattern so future rebuilt pages adopt
it by reference.

## 4. Exact Code Change
Add to the sheet struct:
  - `@State private var isDirty: Bool = false`
  - `@State private var showDiscardAlert: Bool = false`
  - `.onChange(of: <each bound field>) { _, _ in isDirty = true }` on every TextField / Picker / Toggle / DatePicker
  - `.interactiveDismissDisabled(isDirty)` on the outermost NavigationStack/VStack
  - Cancel toolbar button: `if isDirty { showDiscardAlert = true } else { dismiss() }`
  - Discard alert with Discard (destructive) / Keep Editing (cancel) buttons

DO NOT change the save logic, the validation logic, the layout, or any other
behavior. This is a surgical additive pattern only.

## 5. Acceptance Criteria
- [ ] Swipe-down dismissal works on fresh-opened, untouched sheet.
- [ ] Swipe-down is blocked once any field is edited.
- [ ] Tapping Cancel with no changes dismisses immediately.
- [ ] Tapping Cancel with changes shows Discard alert.
- [ ] Save button still works unchanged.
```

---

## Scope List (30+ sheets)

### Phase 1A — People/HR (highest priority — goes first)
_Files under `Weird Parts IOS/Weird Parts IOS/Features/People/`:_

- `NewEmployeeSheet` — very long form, high data-loss stakes
- `EditEmployeeSheet`
- `EditCertificationSheet`
- `NewCertificationSheet`
- `WageEditSheet`
- `NewCustomerSheet`
- `EditCustomerSheet`
- `NewGCSheet` (general contractor)
- `EditGCSheet`
- `NewContactSheet`
- `EditContactSheet`

### Phase 1B — Chat/Messaging
_Files under `Features/Chat/`:_

- `IOSMessageComposerSheet`
- `IOSChannelConfigSheet`
- `IOSThreadCreateSheet`
- `IOSQAEscalateSheet`

### Phase 1C — Orders & Fleet & Scheduling
_Mixed — still high-stakes data entry:_

- `IOSJPOCreationSheet`
- `IOSPOCreationSheet`
- `IOSReceiveShipmentPage` sub-sheets
- `IOSFleetVehicleEditSheet`
- `IOSFleetMaintenanceSheet`
- `IOSScheduleJobSheet`
- `IOSDispatchCreateSheet`
- `IOSTimeOffRequestSheet`

### Phase 1D — Parts & Tools & Settings (lowest data-loss frequency, goes last)
- `PricingBulkEditSheet`, `PricingSettingsSheet`, `PricingOverrideFlow` (in `Features/Parts/`)
- `IOSToolCheckoutSheet`, `IOSToolMaintenanceSheet` (in `Features/Tools/`)
- `IOSSettingsGeneralSheet`, `IOSSettingsTeamsSheet`, `IOSSettingsHatsSheet`, etc. (in `Features/Settings/`)

### Tracking
Each sheet gets:
- A prompt file at `xcode-ai/fix-prompts/PE-NNN-dismiss-guard-<sheet-name>.md`
- An entry in `xcode-ai/fix-prompts/00-fix-order.md` ordered by Phase 1A → 1B → 1C → 1D

---

## Phase 2 — Keyboard Dismiss (#149)

Slots AFTER #143 is fully shipped. Different pattern, different prompt template.

### Pattern
On every scrollable page that contains text fields:

```swift
ScrollView {
    // content
}
.scrollDismissesKeyboard(.interactively)

// Or for List:
List {
    // rows with TextFields
}
.scrollDismissesKeyboard(.interactively)
```

### Prompt template (simpler than #143)
One-liner addition per file. Prompts can be bulk-authored; no 4-section header needed. However, each prompt should still name the specific scrollable container being modified (not "add it everywhere in this file") to keep the change auditable.

### Why separate from #143
- #143 is data loss (critical). #149 is UX annoyance (minor).
- Bundling would dilute the "goal" framing of #143 prompts.
- #149 can be a rapid mechanical pass after #143 lands.

---

## Rollout

1. Write prompts for Phase 1A (People/HR) first — ~11 prompts. Land them sequentially, commit each.
2. After Phase 1A ships and the pattern proves itself, Phase 1B (Chat) — ~4 prompts.
3. Phase 1C (Orders/Fleet/Scheduling) — ~8 prompts.
4. Phase 1D (Parts/Tools/Settings) — ~10+ prompts.
5. Pause, verify no regressions, unit-test the `isDirty` tracking on 2–3 sheets end-to-end.
6. Kick off Phase 2 (#149) as its own campaign.

---

## Test Plan

For each patched sheet:

1. Open sheet, don't touch anything, swipe down → dismisses cleanly (no alert, no block).
2. Open sheet, type into one field, swipe down → blocked (sheet stays up).
3. Open sheet, type, tap Cancel → Discard alert appears.
4. Open sheet, type, tap Cancel → Discard → dismisses, data not saved.
5. Open sheet, type, tap Cancel → Keep Editing → stays on sheet with content intact.
6. Open sheet, type, tap Save → saves, dismisses, `isDirty` doesn't block because we dismissed programmatically post-save.

For #149 (Phase 2): scroll away from a focused text field, verify keyboard follows interactively (comes down as the scroll gesture progresses).

---

## Cross-References

- `feedback_xcode_prompts.md` in MEMORY — reinforces plan-first, rich-context prompt requirement.
- `PE-024` (modal dismiss audit, already closed) — confirmed dismiss patterns are NOT broken in currently-patched sheets, but vast majority untouched.
- GitHub issue `#143` (and `#123`) — interactive dismiss campaign.
- GitHub issue `#149` — keyboard dismiss campaign.
