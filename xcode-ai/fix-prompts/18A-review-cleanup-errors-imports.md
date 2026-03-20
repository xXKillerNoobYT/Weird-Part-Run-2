# 18A — Review Cleanup: Error Visibility, Dead Imports, Minor Bugs

> **Chain position:** Standalone cleanup prompt (run after 17H)
> **Prerequisite:** None — can run independently
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Code review found several issues across Parts category components and other files. These are all small, targeted fixes that don't change functionality — they fix error visibility, remove dead imports, and correct minor UI bugs.

## Task

### Fix 1: Show errors to users in category components (HIGH)

Three files log errors with `print()` but never display them to the user. Add `@State private var loadError: String?` and show it in the UI.

**File: `CategoriesBrandSection.swift`**
Find the catch block that does `print("[CategoriesBrandSection] Load error: \(error)")` and update:

```swift
@State private var loadError: String?

// In the catch block:
catch {
    loadError = error.localizedDescription
    isLoading = false
}

// In the body, before the main content:
if let error = loadError {
    Label(error, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .font(.caption)
}
```

**File: `CategoriesColorPicker.swift`**
Same pattern — find any catch block that only does `print()` and add error state + display.

**File: `TypeBrandColorSection.swift`**
Same pattern — find `print("[TypeBrandColorSection] Load error:")` and replace with user-visible error.

### Fix 2: Remove unused GRDB imports (MEDIUM)

Remove `import GRDB` from files that don't directly use GRDB types. These files should only import `SwiftUI` and `WiredPartCore`:

- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesFormSheets.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardDailyReportPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/IOSDashboardQRScannerPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

Check each file first — only remove `import GRDB` if the file doesn't use any GRDB types (like `Row`, `DatabaseQueue`, `Column`, etc.). If it does use them, leave the import.

### Fix 3: Fix color picker initialization (MEDIUM)

**File: `CategoriesFormSheets.swift`**
In `ColorFormSheet`, find the state initialization:

```swift
@State private var hasColor = true  // BUG: defaults to true even for new colors
```

Change to:
```swift
@State private var hasColor = false  // Default to false for new colors; .onAppear sets true if editing existing
```

This way, creating a new color starts with toggle OFF (no color selected). When editing an existing color with a hex code, `.onAppear` sets it to `true`.

### Fix 4: Add loading state to BrandSupplierPickerSheet save (MEDIUM)

**File: `PartsBrandsPage.swift`**
In `BrandSupplierPickerSheet`, find the Save button and add a saving state:

```swift
@State private var isSaving = false

// On the Save button:
Button {
    Task {
        isSaving = true
        await saveLinks()
        isSaving = false
    }
} label: {
    if isSaving { ProgressView() } else { Text("Save") }
}
.disabled(isSaving)
```

## Important Notes

- These are all small, non-breaking fixes. Each can be tested independently.
- The error visibility pattern (loadError + Label) matches what was done in prompt 02 across the rest of the app.
- Removing GRDB imports is safe cleanup — if any file actually needs it, the build will tell you immediately.
- The color picker fix only changes the default value of a `@State` property. The `.onAppear` handles the edit case correctly already.

## Success Criteria

- [ ] CategoriesBrandSection shows error label when loading fails
- [ ] CategoriesColorPicker shows error label when loading fails
- [ ] TypeBrandColorSection shows error label when loading fails
- [ ] Unused GRDB imports removed (only where safe)
- [ ] Color picker defaults to hasColor=false for new colors
- [ ] BrandSupplierPickerSheet shows spinner + disables Save while saving
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 18A Results (YYYY-MM-DD)
- Error visibility: 3 category components now show errors to users
- Dead imports: removed unused GRDB imports from N files
- Color picker: fixed hasColor default for new colors
- Brand supplier picker: added save loading state
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
