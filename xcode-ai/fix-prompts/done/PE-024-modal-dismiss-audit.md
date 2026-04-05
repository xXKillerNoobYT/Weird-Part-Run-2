# Fix Prompt PE-024: Modal/Sheet Dismiss Audit — All Sheets Must Close

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

Multiple sheets and popups across the app do NOT close when the user taps "Done", "Submit", "Cancel", or the close button. This affects:

- **Part Types** — Done button doesn't close
- **Total Stock** — Not closing properly
- **Active Jobs** — Not closing
- **Pending Orders** — Not closing
- **Report Problem (Daily Report)** — Submit AND Cancel not working
- **Scan Bin** — Popup broken

**GitHub Issue:** #21
**PE Tracker:** PE-024
**Priority:** CRITICAL — users are trapped in popups across the app

---

## Root Cause Pattern

The project uses a shared `SheetDismissWrapper` component that correctly captures `@Environment(\.dismiss)` OUTSIDE its internal `NavigationStack`. Views using this wrapper are fine.

The failures happen in sheets that either:
1. Use `@Environment(\.dismiss)` INSIDE a NavigationStack (picks up nav dismiss, not sheet dismiss)
2. Use a custom "Done" button that sets a `@State` flag but the `.sheet(isPresented:)` binding doesn't observe that flag
3. Have multiple `.sheet()` modifiers on the same view (SwiftUI only activates the last one on iOS 16–)
4. Have the "Submit"/"Done" button trigger async work but don't dismiss afterwards

---

## Fix Pattern

**Correct pattern for any sheet that needs a Done/Close button:**

```swift
// OPTION A: Use SheetDismissWrapper (preferred for standard sheets)
struct MySheet: View {
    var body: some View {
        SheetDismissWrapper(title: "My Sheet") {
            MyContent()
        }
    }
}

// OPTION B: When inside your own NavigationStack, capture dismiss BEFORE the stack
struct MySheet: View {
    @Environment(\.dismiss) private var dismiss  // ← MUST be at this level
    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// OPTION C: For Cancel/Submit buttons in a form (no NavigationStack)
struct MyFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            // ...form content...
            HStack {
                Button("Cancel") { dismiss() }
                Button("Submit") {
                    saveData()
                    dismiss()  // ← always call dismiss() after action
                }
            }
        }
    }
}
```

**DO NOT:**
- Put `@Environment(\.dismiss)` inside a `NavigationStack` body
- Forget to call `dismiss()` after an async save operation completes
- Use multiple `.sheet()` modifiers on the same view — combine them into one `.sheet(item:)` with an enum

---

## Files to Audit and Fix

Work through these in priority order:

### 1. Report Problem Sheet (Daily Report) — Submit AND Cancel broken

**File:** `Features/Dashboard/DashboardDailyReportPage.swift`

Find the `ReportProblemSheet` struct or wherever the "Report Problem" popup is defined (search for `struct ReportProblemSheet` or `case reportProblem`).

- Verify `@Environment(\.dismiss)` is captured OUTSIDE any NavigationStack
- Verify `dismiss()` is called on both Cancel and after successful Submit
- If Submit is async, call `dismiss()` in the completion handler after the save

### 2. Scan Bin Popup — not dismissing

**File:** Search for `ScanBinSheet` or wherever the "Scan Bin" popup is defined. Same audit as above.

### 3. Daily Report — all sheet modifiers

**File:** `Features/Dashboard/DashboardDailyReportPage.swift`

Search for all `.sheet()` and `.fullScreenCover()` modifiers in this file. If there are multiple `.sheet()` modifiers on the same view chain, consolidate them into a single `.sheet(item:)` using an enum (the same pattern used in `DashboardView.swift`).

### 4. Check all pages with multiple .sheet() modifiers

Run a search for files that have more than one `.sheet(` call. For each file that has multiple `.sheet()` modifiers:
- Consolidate into a single `.sheet(item: $activeSheet)` using an enum
- This fixes the SwiftUI bug where only the last `.sheet()` in a chain fires

### 5. Verify KPI Detail sheets still work after your changes

Open `DashboardKPIDetailSheets.swift` — the KPI detail sheets (Part Types, Total Stock, Active Jobs, Pending Orders) use `SheetDismissWrapper`. These should be fine, but verify Done still works after any changes to DashboardView.

---

## Success Criteria

- Every sheet in the app closes when the user taps Done, Cancel, Close, or Submit (after save completes)
- No sheet leaves the user stranded with no way to exit
- All `.sheet()` modifiers use the `.sheet(item:)` enum pattern (not multiple separate `.sheet(isPresented:)`)
- `@Environment(\.dismiss)` is never captured inside a NavigationStack body

---

## After Completing

Log results in `xcode-ai/prompt-results-log.md` with the standard format. Mark PE-024 DONE in `xcode-ai/fix-prompts/00-fix-order.md`.
