# Prompt 15B — Brands & Suppliers: Delete Confirmation + Save Error Feedback

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Fix three issues across both Brands and Suppliers pages:
1. Swipe-to-delete has no confirmation — instant delete is dangerous
2. Save errors in form sheets are invisible (print-only)
3. Delete errors are invisible (print-only)

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift`

## Pattern: Delete Confirmation

Apply to **both** pages. For each swipe delete action, add an alert confirmation.

### In PartsBrandsPage:

Add state variables:

```swift
@State private var brandToDelete: BrandListRow?
@State private var showDeleteConfirm = false
@State private var deleteError: String?
```

Replace the swipe delete button's action (currently calls `deleteBrand` directly):

```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        brandToDelete = brand
        showDeleteConfirm = true
    } label: {
        Label("Delete", systemImage: "trash")
    }
    // ... edit button stays
}
```

Add the confirmation alert to the main body (on the `VStack`):

```swift
.alert("Delete Brand?", isPresented: $showDeleteConfirm) {
    Button("Cancel", role: .cancel) { brandToDelete = nil }
    Button("Delete", role: .destructive) {
        if let brand = brandToDelete {
            Task { await deleteBrand(brand) }
        }
    }
} message: {
    if let brand = brandToDelete {
        Text("Delete \"\(brand.name)\"? This cannot be undone. \(brand.partCount) part(s) use this brand.")
    }
}
```

Update `deleteBrand()` to show errors:

```swift
private func deleteBrand(_ brand: BrandListRow) async {
    guard let service = appCore.partsService else { return }
    do {
        try service.deleteBrand(id: brand.id)
        brandToDelete = nil
        await loadData()
    } catch {
        deleteError = "Failed to delete \(brand.name): \(error.localizedDescription)"
    }
}
```

Add error banner at top of the list (inside the `brandsList` view):

```swift
if let error = deleteError {
    Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.caption)
    }
}
```

### In PartsSuppliersPage:

Apply the exact same pattern with `supplierToDelete`, `showDeleteConfirm`, `deleteError`.

## Pattern: Save Error Feedback

Apply to **both** form sheets (`BrandFormSheet` and `SupplierFormSheet`).

### In each form sheet, add:

```swift
@State private var saveError: String?
@State private var isSaving = false
```

### Show error in form:

```swift
if let error = saveError {
    Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.subheadline)
    }
}
```

### Update Save button:

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

### Add saveAndDismiss method:

```swift
private func saveAndDismiss() async {
    isSaving = true
    saveError = nil
    do {
        try await save()   // save() should throw (updated in 15A)
        await onSave()
        dismiss()
    } catch {
        saveError = error.localizedDescription
    }
    isSaving = false
}
```

### Remove the old inline Task in the toolbar Save button

Replace:
```swift
Button("Save") {
    Task {
        await save()
        await onSave()
        dismiss()
    }
}
```

With the new `saveAndDismiss()` call above.

### Remove all `print()` error statements

Search for `print("[BrandFormSheet]`, `print("[PartsBrandsPage]`, `print("[SupplierFormSheet]`, `print("[PartsSuppliersPage]` and remove them. Errors are now shown in the UI.

## Logging

After completing this prompt, append results to `xcode-ai/prompt-results-log.md`.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] Swipe-to-delete on Brands shows confirmation alert with part count
- [ ] Swipe-to-delete on Suppliers shows confirmation alert
- [ ] Delete errors shown as inline red banner
- [ ] Save errors shown inline in form sheets (red label)
- [ ] Save button shows spinner while saving
- [ ] Forms don't dismiss on save failure
- [ ] No `print()` error statements remain in either file

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/15C-supplier-detail-nested-sheet.md`.
