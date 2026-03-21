# Prompt 14C — Categories: Search Field at Top of Tree

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Add a search field at the top of the Categories tree panel so users can quickly find categories, styles, types, brands, or colors by name. The search filters the tree to show only matching nodes (and their parent chain).

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

## Step 1: Add Search State

Add a new state variable near the existing state:

```swift
@State private var searchText = ""
```

## Step 2: Add Search Bar to Header

In the `body` property, add a search field between the header and the content. Find the existing header `HStack` with "Parts Hierarchy" and the `+` menu. Add the search field right after `Divider()`:

```swift
// Search field
HStack(spacing: DS.Space.sm) {
    Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .font(.subheadline)
    TextField("Search hierarchy...", text: $searchText)
        .textFieldStyle(.plain)
        .font(.subheadline)
    if !searchText.isEmpty {
        Button {
            searchText = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .buttonStyle(.plain)
    }
}
.padding(.horizontal, DS.Space.lg)
.padding(.vertical, DS.Space.sm)
.background(Color(.secondarySystemGroupedBackground))
.clipShape(RoundedRectangle(cornerRadius: 8))
.padding(.horizontal, DS.Space.lg)
.padding(.bottom, DS.Space.sm)
```

## Step 3: Add Filtered Hierarchy Computed Property

Add a computed property that filters the hierarchy based on search text:

```swift
/// Filters the hierarchy tree to only show nodes matching the search query.
/// When a child matches, all its ancestors are included to preserve the tree path.
private var filteredCategories: [PartsService.CategoryNode] {
    guard !searchText.isEmpty else { return hierarchy.categories }
    let query = searchText.lowercased()

    return hierarchy.categories.compactMap { catNode -> PartsService.CategoryNode? in
        // Check if category name matches
        let catMatches = catNode.category.name.lowercased().contains(query)

        // Filter styles
        let filteredStyles = catNode.styles.compactMap { styleNode -> PartsService.StyleNode? in
            let styleMatches = styleNode.style.name.lowercased().contains(query)

            // Filter types
            let filteredTypes = styleNode.types.compactMap { typeNode -> PartsService.TypeNode? in
                let typeMatches = typeNode.type.name.lowercased().contains(query)

                // Check brands and colors
                let hasBrandMatch = typeNode.brandNodes.contains { brandNode in
                    brandNode.name.lowercased().contains(query) ||
                    brandNode.colors.contains { $0.name.lowercased().contains(query) }
                }

                if typeMatches || hasBrandMatch {
                    return typeNode
                }
                return nil
            }

            if styleMatches || !filteredTypes.isEmpty {
                return PartsService.StyleNode(
                    style: styleNode.style,
                    types: filteredTypes.isEmpty && styleMatches ? styleNode.types : filteredTypes
                )
            }
            return nil
        }

        if catMatches || !filteredStyles.isEmpty {
            return PartsService.CategoryNode(
                category: catNode.category,
                styles: filteredStyles.isEmpty && catMatches ? catNode.styles : filteredStyles
            )
        }
        return nil
    }
}
```

## Step 4: Use Filtered Data in the Tree

Replace all references to `hierarchy.categories` in the `body` (the `ForEach` loop that renders category sections) with `filteredCategories`:

Find:
```swift
ForEach(hierarchy.categories) { catNode in
    categorySection(catNode)
}
```

Replace with:
```swift
ForEach(filteredCategories) { catNode in
    categorySection(catNode)
}
```

Also update the empty state check:

```swift
if filteredCategories.isEmpty {
    if searchText.isEmpty {
        EmptyStateView(
            icon: "folder.badge.questionmark",
            title: "No Categories Yet",
            message: "Create categories to organize your parts hierarchy.",
            actionLabel: "Add Category"
        ) {
            activeSheet = .addCategory
        }
    } else {
        ContentUnavailableView.search(text: searchText)
    }
}
```

## Step 5: Auto-Expand on Search

When the user types a search query, auto-expand all matching nodes so results are visible:

```swift
.onChange(of: searchText) {
    if !searchText.isEmpty {
        // Auto-expand all categories and styles in filtered results
        for catNode in filteredCategories {
            if let catId = catNode.category.id {
                expandedCategories.insert(catId)
            }
            for styleNode in catNode.styles {
                if let styleId = styleNode.style.id {
                    expandedStyles.insert(styleId)
                }
                for typeNode in styleNode.types {
                    if let typeId = typeNode.type.id {
                        expandedTypes.insert(typeId)
                    }
                }
            }
        }
    }
}
```

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] Search field visible at top of tree panel, below the header
- [ ] Typing filters the tree to matching nodes only
- [ ] Matching preserves parent chain (if a Type matches, its parent Style and Category show)
- [ ] Search matches against category, style, type, brand, and color names
- [ ] Clear button (x) resets search and shows full tree
- [ ] Empty search results show `ContentUnavailableView.search`
- [ ] Matched nodes auto-expand so results are visible without manual expanding

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14D-categories-form-error-feedback.md`.
