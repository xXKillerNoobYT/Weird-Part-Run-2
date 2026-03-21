# Prompt 15C — Fix SupplierDetailSheet Nested Sheet Conflict

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

`SupplierDetailSheet` in `PartsSuppliersPage.swift` has a nested `.sheet(isPresented:)` on line ~552. Since `SupplierDetailSheet` is already presented as a sheet item from the parent page, this nested sheet causes SwiftUI dismissal conflicts. Fix it using the single-sheet enum pattern.

## File to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift`

## The Fix

### Option A: Move Edit into Parent's ActiveSheet (Preferred)

Add an edit case to the parent page's `ActiveSheet` enum:

```swift
enum ActiveSheet: Identifiable {
    case addSupplier
    case supplierDetail(SupplierListRow)
    case editSupplier(SupplierListRow)  // ADD THIS

    var id: String {
        switch self {
        case .addSupplier: return "addSupplier"
        case .supplierDetail(let s): return "detail-\(s.id)"
        case .editSupplier(let s): return "edit-\(s.id)"
        }
    }
}
```

Update the parent `.sheet(item:)` to handle the edit case:

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .addSupplier:
        SupplierFormSheet(supplier: nil) { await loadData() }
    case .supplierDetail(let supplier):
        SupplierDetailSheet(supplier: supplier, onEdit: {
            // Dismiss detail, then open edit
            activeSheet = .editSupplier(supplier)
        }, onUpdate: { await loadData() })
    case .editSupplier(let supplier):
        SupplierFormSheet(supplier: supplier) { await loadData() }
    }
}
```

### Update SupplierDetailSheet

Remove the `.sheet(isPresented: $showEditForm)` and `@State private var showEditForm` from `SupplierDetailSheet`.

Add an `onEdit` closure parameter:

```swift
struct SupplierDetailSheet: View {
    let supplier: SupplierListRow
    var onEdit: () -> Void     // ADD THIS
    let onUpdate: () async -> Void
    // ...
}
```

Change the edit button in the toolbar to call the closure:

```swift
ToolbarItem(placement: .automatic) {
    Button {
        dismiss()
        onEdit()
    } label: {
        Image(systemName: "pencil")
    }
}
```

Remove the nested `.sheet(isPresented: $showEditForm)` entirely.

## Logging

After completing this prompt, append results to `xcode-ai/prompt-results-log.md`.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] No nested `.sheet` inside `SupplierDetailSheet`
- [ ] Tapping edit on supplier detail dismisses detail and opens edit form
- [ ] Edit form saves and refreshes the list correctly
- [ ] Only one `.sheet(item:)` modifier on the parent view

## Next

When all criteria are met, the Brands & Suppliers page improvements are complete. Return to `xcode-ai/fix-prompts/00-fix-order.md` for the next page to review.
