# 32H — Add Missing .refreshable and .searchable (58 Files)

> **Chain position:** **32H** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. EVERY List view must have `.refreshable { await loadData() }` or `.refreshable { loadData() }`
2. EVERY list with 10+ items should have `.searchable(text: $searchText, prompt: "Search...")`
3. If `.refreshable` requires async, make `loadData()` async or wrap: `.refreshable { Task { loadData() } }`

## Instructions

Search ALL `.swift` files in `Weird Parts IOS/Weird Parts IOS/Features/` for views that use `List` but are missing `.refreshable` or `.searchable`.

### Adding .refreshable

If a view has a `List { ... }` and a `loadData()` function but no `.refreshable`:

```swift
// Add to the List or its container:
.refreshable { loadData() }
```

If `loadData()` is async:
```swift
.refreshable { await loadData() }
```

### Adding .searchable

If a view shows a list of items (parts, jobs, employees, etc.) that could have 10+ entries:

```swift
@State private var searchText = ""

// Add to the view:
.searchable(text: $searchText, prompt: "Search...")

// Filter the data:
private var filteredItems: [ItemType] {
    guard !searchText.isEmpty else { return items }
    let query = searchText.lowercased()
    return items.filter { $0.name.lowercased().contains(query) }
}
```

### Files to Check

Check EVERY file under Features/ that contains a `List`. If it's missing either modifier, add it. Only skip if the list is always short (< 5 items, like a settings page with 3 options).

## Success Criteria

- [ ] Every List view in Features/ has `.refreshable`
- [ ] Every searchable list (10+ items possible) has `.searchable`
- [ ] No compilation errors from missing async/await
- [ ] Project builds with no errors
