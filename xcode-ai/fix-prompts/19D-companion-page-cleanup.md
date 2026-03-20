# 19D — Companion Page Cleanup: Raw SQL → Service, Errors, Guards

## Context
You are working on a SwiftUI iOS app. `PartsCompanionsPage.swift` (635 lines) uses raw SQL via `import GRDB`, has hard deletes, swallows errors with `print()`, and has `#if os(iOS)` guards. Prompts 19A-19C added service methods to `PartsService` that should replace all raw SQL.

**Available PartsService methods (added in 19B/19C):**
- `listCompanionRulesHierarchy()` → `[CompanionRuleHierarchyRow]`
- `deleteCompanionRuleSoft(id:)` — soft delete with child cascade
- `restoreCompanionRule(id:)` — restore deleted rule + children
- `updateCompanionRule(id:, isActive:)` — toggle active/inactive
- `listAllAlternatives()` → `[PartAlternativeWithName]`
- `unlinkPartAlternative(linkId:)` — remove alternative link

**Current bugs:**
1. `import GRDB` — raw SQL throughout loadData(), deleteRule(), toggleRuleActive(), deleteAlternative()
2. Hard deletes: `DELETE FROM companion_rules WHERE id = ?` — should be soft delete
3. `print()` error swallowing — no user-visible error messages
4. `#if os(iOS)` / `#elseif os(macOS)` guards (lines 80-84, 179-181, 263-265) — this is iOS-only
5. No delete confirmation — swipe-to-delete has no alert
6. `CompanionRuleRow` struct doesn't show hierarchy info (parent/child, orphan status)
7. Rule list doesn't show source→target categories, just rule name and description

## Task

### 1. Remove `import GRDB` (line 2)

Delete `import GRDB` — all data access goes through `PartsService`.

### 2. Replace `CompanionRuleRow` with service type

Replace the local `CompanionRuleRow` struct (line 399-406) with the service's `CompanionRuleHierarchyRow`. Update `@State private var companionRules` to use `[PartsService.CompanionRuleHierarchyRow]`.

### 3. Replace `AlternativeRow` with service type

Replace the local `AlternativeRow` struct (line 408-416) with `PartsService.PartAlternativeWithName`. The alternatives list should use `listAllAlternatives()`.

### 4. Rewrite `loadData()` (lines 291-351)

Replace the raw SQL with:
```swift
@Sendable
private func loadData() async {
    isLoading = true
    loadError = nil
    do {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        let rules = try service.listCompanionRulesHierarchy()
        let alts = try service.listAllAlternatives()
        await MainActor.run {
            companionRules = rules
            alternatives = alts
            isLoading = false
        }
    } catch {
        await MainActor.run {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

### 5. Rewrite `deleteRule()` (lines 355-365)

Replace hard delete with soft delete + confirmation alert:

Add state variables:
```swift
@State private var ruleToDelete: PartsService.CompanionRuleHierarchyRow?
@State private var showDeleteConfirm = false
@State private var actionError: String?
```

The swipe action should set `ruleToDelete = rule` and `showDeleteConfirm = true` instead of immediately deleting. Add an `.alert("Delete Rule?", isPresented: $showDeleteConfirm)` that:
- Shows the rule name
- If the rule has children: warns "This will also schedule X child rules for deletion in 30 days."
- On confirm: calls `service.deleteCompanionRuleSoft(id:)` then reloads
- On error: sets `actionError`

### 6. Rewrite `toggleRuleActive()` (lines 367-378)

Replace raw SQL with: `try service.updateCompanionRule(id: rule.id, isActive: rule.isActive == 1 ? 0 : 1)`

### 7. Rewrite `deleteAlternative()` (lines 380-390)

Replace raw SQL with: `try service.unlinkPartAlternative(linkId: alt.id)`. Add a confirmation alert.

### 8. Add "Restore" swipe action for deleted rules

For rules where `deletedAt != nil` or `autoDeleteAt != nil`, add a swipe action:
```swift
Button {
    Task { await restoreRule(rule) }
} label: {
    Label("Restore", systemImage: "arrow.uturn.backward")
}
.tint(.blue)
```

The `restoreRule()` method calls `service.restoreCompanionRule(id:)`.

### 9. Update rule list display

The rules list should show:
- **Source → Target** names (from sources/targets arrays, not just rule name)
- **Match level badge**: "Category", "Style", or "Type" in a colored capsule
- **Brand match indicator**: if tryMatchBrand == 1, show a small "Brand" badge
- **Orphan indicator**: if `isOrphaned`, show the row with red tint and "Deleting in X days" text
- **Child count**: if childCount > 0, show "(X sub-rules)" text
- **Active/Inactive** status

### 10. Remove all `#if os(iOS)` / `#elseif os(macOS)` guards

Remove lines like:
```swift
#if os(iOS)
.listStyle(.insetGrouped)
#endif
```
Replace with just:
```swift
.listStyle(.insetGrouped)
```

And:
```swift
#if os(iOS)
.background(DS.Background.page)
#elseif os(macOS)
.background(DS.Background.page)
#endif
```
Replace with just:
```swift
.background(DS.Background.page)
```

### 11. Add error banner

Add an error banner for action errors (delete, toggle, restore failures):
```swift
if let error = actionError {
    HStack {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
        Text(error)
            .font(.caption)
        Spacer()
        Button("Dismiss") { actionError = nil }
            .font(.caption)
    }
    .padding(8)
    .background(.red.opacity(0.1))
    .cornerRadius(8)
    .padding(.horizontal)
}
```

## Success Criteria
- [ ] `import GRDB` removed — no raw SQL anywhere in the file
- [ ] All data loading uses PartsService methods
- [ ] Soft delete with confirmation alert (shows child count warning)
- [ ] Restore action available for deleted/orphaned rules
- [ ] Rule list shows source→target names, match level badge, brand indicator, orphan status
- [ ] All `#if os(iOS)` / `#elseif os(macOS)` guards removed
- [ ] Error banner for action failures
- [ ] No `print()` error swallowing
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19D Results (YYYY-MM-DD)
- Removed import GRDB, all raw SQL replaced with PartsService calls
- Added soft delete with confirmation alerts (child cascade warning)
- Added restore swipe action for deleted/orphaned rules
- Updated rule list: source→target names, match level badges, orphan indicators
- Removed all #if os(iOS) guards
- Added actionError banner, removed print() swallowing
- Build: [PASS/FAIL]
```

When done, start prompt 19E next.
