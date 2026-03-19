# Fix Prompt 01: Sheet/Popup Dismissal Issues

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

When a user opens a popup form (like "Add Vehicle", "Edit Job", "Create Trailer"), fills it out, and taps Save — sometimes the popup doesn't close. Other times it closes but the list behind it still shows old data. Some popups won't even open at all because another popup is "blocking" it.

This happens because SwiftUI only supports ONE `.sheet` modifier per view. When multiple `.sheet` modifiers are stacked on the same view, only one works — the others silently break.

---

## Files To Fix

### Priority 1: Multiple `.sheet` on same view (popups won't open/close)

**`Features/Parts/CategoriesEditorPanel.swift`** — Has 7 `.sheet` modifiers on one view. Consolidate into a single `.sheet(item:)` using an enum:

```swift
enum ActiveSheet: Identifiable {
    case addStyle(Int64)      // category ID
    case addType(Int64)       // style ID
    case addColor
    case editCategory(CategoriesService.CategoryNode)
    case editStyle(CategoriesService.StyleNode)
    case editType(CategoriesService.TypeNode)
    case editColor(CategoriesService.ColorNode)

    var id: String {
        switch self {
        case .addStyle(let id): return "addStyle-\(id)"
        case .addType(let id): return "addType-\(id)"
        case .addColor: return "addColor"
        case .editCategory(let c): return "editCat-\(c.id)"
        case .editStyle(let s): return "editStyle-\(s.id)"
        case .editType(let t): return "editType-\(t.id)"
        case .editColor(let c): return "editColor-\(c.id)"
        }
    }
}

@State private var activeSheet: ActiveSheet?
```

Then replace all 7 `.sheet(...)` calls with one:
```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .addStyle(let catId):
        AddStyleFormSheet(categoryId: catId, onSave: { loadData() })
    case .addType(let styleId):
        AddTypeFormSheet(styleId: styleId, onSave: { loadData() })
    // ... etc
    }
}
```

**`Features/Parts/CategoriesTreeView.swift`** — Has 4 `.sheet` modifiers. Same fix — consolidate into one `.sheet(item:)` enum.

**`Navigation/IOSMainView.swift`** — Has multiple `.sheet` modifiers for AI assistant, user menu, and tab editor. These are on different view branches (`fullSidebarView` vs `moreTab`) so they may not all conflict, but the AI assistant sheet appears on both branches. Consolidate any that share a parent.

### Priority 2: Sheets that don't reload data when dismissed

These sheets present forms but the parent page never reloads data after the form closes. User saves something → popup closes → list still shows old items.

Fix pattern — add `onSave` callback or `onChange`:

**`Features/Jobs/JobsListPage.swift`** (line 41):
```swift
// CURRENT (no reload)
.sheet(isPresented: $showCreateJob) {
    IOSCreateJobSheet()
}

// FIX (reload after create)
.sheet(isPresented: $showCreateJob) {
    IOSCreateJobSheet(onSave: { loadData() })
}
// OR add:
.onChange(of: showCreateJob) { _, isShowing in
    if !isShowing { loadData() }
}
```

Apply the same pattern to ALL of these:
- `Features/Jobs/IOSJobDetailTabView.swift` line 62 — `showEditSheet`
- `Features/Jobs/IOSClockPage.swift` line 41 — `showClockInSheet`
- `Features/Jobs/LaborPage.swift` line 41 — `showClockIn`
- `Features/Fleet/IOSVehiclesPage.swift` line 43 — `showCreateVehicle`
- `Features/Fleet/IOSTrailersPage.swift` line 36 — `showCreateTrailer`
- `Features/Fleet/IOSVehicleDetailPage.swift` line 38 — `showAssignDriver`
- `Features/Office/IOSManageJobsPage.swift` line 47 — `showCreateJob`
- `Features/Settings/CompanyProfilesPage.swift` line 81 — `showEditor`
- `Features/Parts/PartsBrandsPage.swift` line 37 — `showAddBrand`
- `Features/Parts/PartsCatalogPage.swift` line 105 — `showAddPart`
- `Features/Parts/PartsSuppliersPage.swift` line 50 — `showAddSupplier`
- `Features/Parts/PartsCompanionsPage.swift` lines 57, 60 — `showAddRule`, `showAddAlternative`

For each one: when the sheet's `isPresented` boolean goes from `true` → `false`, call `loadData()`.

---

## Testing Checklist

After making these changes, test each one:
1. Open a form popup → fill it out → tap Save → popup should close AND the list should show the new item
2. Open a form popup → tap Cancel → popup should close, list unchanged
3. In CategoriesEditorPanel: try opening Add Style, then close it, then open Edit Category — both should work
4. In IOSMainView: open AI assistant, close it, open User Menu — both should work without conflict

---

## When Done

Start **prompt 02 (Error Visibility)** next.
