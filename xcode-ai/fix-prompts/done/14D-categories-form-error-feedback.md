# Prompt 14D — Categories: Save Error Feedback in Form Sheets

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

All 4 form sheets in the Categories section currently use `print()` for save errors — the user gets zero feedback if a save fails. Fix all of them to show inline error messages and prevent dismissal on failure.

## File to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesFormSheets.swift`

## Pattern to Apply (same for all 4 sheets)

Each form sheet (`CategoryFormSheet`, `StyleFormSheet`, `TypeFormSheet`, `ColorFormSheet`) needs:

### A. Add error + saving state

Add to each sheet's `@State` variables:

```swift
@State private var saveError: String?
@State private var isSaving = false
```

### B. Show error in the form

Add an error section at the bottom of the `Form`, before the closing brace:

```swift
if let error = saveError {
    Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.subheadline)
    }
}
```

### C. Update the Save button

Change the Save toolbar button to show a spinner while saving and prevent double-taps:

```swift
ToolbarItem(placement: .confirmationAction) {
    Button {
        Task { await saveAndDismiss() }
    } label: {
        if isSaving {
            ProgressView()
        } else {
            Text("Save")
        }
    }
    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
}
```

### D. Refactor save into saveAndDismiss

Replace the inline `Task { await save(); await onSave(); dismiss() }` pattern. Create a new method that only dismisses on success:

```swift
private func saveAndDismiss() async {
    isSaving = true
    saveError = nil
    do {
        try await save()  // make save() throw
        await onSave()
        dismiss()
    } catch {
        saveError = error.localizedDescription
    }
    isSaving = false
}
```

### E. Make save() throw instead of catching internally

Change each sheet's `save()` method from:

```swift
private func save() async {
    // ...
    do {
        // ... service call
    } catch {
        print("[CategoryFormSheet] Save error: \(error)")
    }
}
```

To:

```swift
private func save() async throws {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { throw PartsError.categoryNotFound }
    guard let service = appCore.partsService else {
        throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
    }
    // ... service call (no try/catch here — let it propagate)
}
```

## Apply to All 4 Sheets

Apply steps A-E to each of these structs in `CategoriesFormSheets.swift`:

1. **CategoryFormSheet** (line ~14)
2. **StyleFormSheet** (line ~81)
3. **TypeFormSheet** (line ~149)
4. **ColorFormSheet** (line ~217)

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] All 4 form sheets show inline red error message if save fails
- [ ] Save button shows spinner while saving
- [ ] Sheet does NOT dismiss if save fails — stays open with error visible
- [ ] Save button disabled during save (prevents double-tap)
- [ ] No `print()` statements for save errors remain (remove them)
- [ ] Successful saves still dismiss and refresh as before

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14E-categories-smart-delete.md`.
