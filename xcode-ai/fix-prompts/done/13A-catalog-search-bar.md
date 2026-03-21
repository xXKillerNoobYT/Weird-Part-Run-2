# Fix Prompt 13A: Catalog Page — Fixed Search Bar at Top

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## What the User Wants

The search bar on the Parts Catalog page looks awkward and disappears when you scroll. It should be **fixed at the top of the page, always visible**, so users can search at any time without scrolling back up.

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`**

### What To Change

1. **Remove** the `.searchable(text: $searchText, ...)` modifier (around line 98). This is the SwiftUI default that hides on scroll.

2. **Add** a custom search bar `TextField` at the top of the `body` VStack, BEFORE the filter bar and list. This stays pinned:

```swift
var body: some View {
    VStack(spacing: 0) {
        // Fixed search bar — always visible, never scrolls away
        searchBar

        // Filter chips — always visible (prompt 13B will handle this)
        if showFilters {
            filterBar
        }

        // Sort header
        sortHeader

        // Content...
        if isLoading {
            // ...existing code
```

3. **Create** the `searchBar` computed property:

```swift
@ViewBuilder
private var searchBar: some View {
    HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)

        TextField("Search parts by name, code, or brand...", text: $searchText)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .submitLabel(.search)

        if !searchText.isEmpty {
            Button {
                searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding(.horizontal, DS.Space.lg)
    .padding(.top, DS.Space.sm)
    .padding(.bottom, DS.Space.xs)
}
```

4. **Keep** the existing `.onChange(of: searchText)` handler that calls `resetAndLoad()` — it still works with a TextField.

5. **Remove** the `.searchable` modifier completely. If you get a compile error about `.searchable` being referenced elsewhere, search the file for any other `.searchable` usage.

---

## Success Criteria

1. Search bar is always visible at the top of the Catalog page
2. Typing in the search bar filters parts by name, code, or brand (same as before)
3. "X" button in the search bar clears the text
4. Search bar does NOT scroll away when the list scrolls down
5. Search bar looks clean — rounded background, search icon on left

---

## When Done

Read and implement **prompt 13B-catalog-filter-chips.md** next.
