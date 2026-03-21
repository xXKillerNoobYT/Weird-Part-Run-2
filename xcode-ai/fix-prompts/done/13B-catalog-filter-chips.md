# Fix Prompt 13B: Catalog Page — Always-Visible Filter Chips

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompt 13A must be completed first (fixed search bar).

---

## What the User Wants

The filter bar currently requires tapping a toolbar button to show/hide it. The user wants filter chips **always visible** below the search bar — no toggle needed. This makes filtering much faster: see your options, tap to filter, tap again to clear.

Note: This is about the **FILTERS** (Category, Style, Type, Color, Brand, Low Stock) — NOT the sort buttons. The sort header row can stay as-is below the filters.

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`**

### What To Change

1. **Remove** the `showFilters` state variable (around line 38):
```swift
// DELETE this line:
@State private var showFilters = false
```

2. **Remove** the toolbar filter toggle button (around line 103-109):
```swift
// DELETE this button from the toolbar:
Button {
    withAnimation { showFilters.toggle() }
} label: {
    Image(systemName: showFilters
          ? "line.3.horizontal.decrease.circle.fill"
          : "line.3.horizontal.decrease.circle")
}
```

3. **Remove** the `if showFilters` conditional around `filterBar` in the body (around line 79-81). The filter bar should ALWAYS show:

```swift
// CHANGE from:
if showFilters {
    filterBar
}

// TO (always visible):
filterBar
```

4. **Improve the filter chip styling** — make active filters more visually distinct. Update the `filterMenu` helper to use bolder highlighting:

```swift
@ViewBuilder
private func filterMenu(
    label: String,
    icon: String,
    selection: Int64?,
    options: [(Int64?, String)],
    onChange: @escaping (Int64?) -> Void
) -> some View {
    Menu {
        Button("All \(label)s") { onChange(nil) }
        Divider()
        ForEach(options, id: \.0) { id, name in
            Button {
                onChange(id)
            } label: {
                if selection == id {
                    Label(name, systemImage: "checkmark")
                } else {
                    Text(name)
                }
            }
        }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(selection.flatMap { sel in options.first { $0.0 == sel }?.1 } ?? label)
                .font(.caption)
                .fontWeight(selection != nil ? .semibold : .regular)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(selection != nil
                ? Color.accentColor.opacity(0.15)
                : Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            Capsule().stroke(selection != nil
                ? Color.accentColor.opacity(0.4)
                : Color.clear, lineWidth: 1)
        )
    }
}
```

5. **Add a count badge** to the filter bar showing how many filters are active:

In the `filterBar` view, after the "Clear" button, add a badge showing the count if 2+ filters are active:

```swift
// At the end of the HStack in filterBar, before the closing brace:
if hasActiveFilters {
    Button {
        clearAllFilters()
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "xmark")
                .font(.caption2)
            Text("Clear")
                .font(.caption)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.red.opacity(0.08)))
    }
}
```

---

## Success Criteria

1. Filter chips are ALWAYS visible below the search bar — no toggle button
2. The toolbar no longer has a filter toggle icon (only the "+" add part button remains)
3. Active filters show highlighted chips (blue tint background + border)
4. Tapping a chip opens a dropdown menu with all options + checkmark on selected
5. "Clear" button appears when any filter is active, clears everything
6. Cascading filters still work: selecting a Category filters the Style dropdown, etc.

---

## When Done

Read and implement **prompt 13C-catalog-detail-sheet.md** next.
