# Prompt 14B — Categories: Alphabetical Sort + Count Badges + Bigger Add Buttons

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Three UX improvements to the Categories tree:
1. Sort all nodes alphabetically (A-Z) at every level
2. Add count badges on collapsed nodes for quick scanning
3. Make inline "Add Style" / "Add Type" buttons more prominent

## Files to Modify

1. `core/Sources/WiredPartCore/Services/PartsService.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

## Step 1: Alphabetical Sorting in Service Layer

**File:** `core/Sources/WiredPartCore/Services/PartsService.swift`

In the `getHierarchy()` method, ensure all SQL queries use `ORDER BY name ASC` instead of `ORDER BY sort_order ASC` or any other ordering. Apply this to:

- Categories query: `ORDER BY name ASC`
- Styles query: `ORDER BY name ASC`
- Types query: `ORDER BY name ASC`
- Brands (within BrandNode building): `ORDER BY name ASC` (should already be set from 14A)
- Colors: `ORDER BY name ASC`

If the queries currently use `sort_order`, replace with `name`. Keep `sort_order` columns in the database — they just won't be used for display ordering.

## Step 2: Count Badges on Tree Nodes

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

### 2A. Add a badge helper

Add this method to `CategoriesTreeView`:

```swift
// MARK: - Count Badge

@ViewBuilder
private func countBadge(_ count: Int) -> some View {
    Text("\(count)")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.accentColor.opacity(0.8)))
}
```

### 2B. Add badges to treeRow

Update the `treeRow` builder to accept an optional count and show a badge:

```swift
private func treeRow(icon: String, iconColor: Color, title: String, subtitle: String, isSelected: Bool, badgeCount: Int? = nil) -> some View {
    HStack(spacing: DS.Space.sm) {
        Image(systemName: icon)
            .foregroundStyle(iconColor)
            .font(.subheadline)
            .frame(width: 20)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Spacer()
        if let count = badgeCount, count > 0 {
            countBadge(count)
        }
    }
    .padding(.vertical, DS.Space.xs)
    .padding(.trailing, DS.Space.sm)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
}
```

### 2C. Pass badge counts when calling treeRow

In `categorySection`, pass the total descendant count (styles + types + brands):

```swift
treeRow(
    icon: "folder.fill",
    iconColor: .accentColor,
    title: catNode.category.name,
    subtitle: "\(catNode.styles.count) style\(catNode.styles.count == 1 ? "" : "s")",
    isSelected: isSelected,
    badgeCount: isExpanded ? nil : catNode.styles.count
)
```

In `styleSection`, pass type count:

```swift
treeRow(
    icon: "paintbrush.fill",
    iconColor: .purple,
    title: styleNode.style.name,
    subtitle: "\(styleNode.types.count) type\(styleNode.types.count == 1 ? "" : "s")",
    isSelected: isSelected,
    badgeCount: isExpanded ? nil : styleNode.types.count
)
```

In `typeSection`, pass brand count:

```swift
treeRow(
    icon: "wrench.and.screwdriver.fill",
    iconColor: .teal,
    title: typeNode.type.name,
    subtitle: "\(typeNode.brandNodes.count) brand\(typeNode.brandNodes.count == 1 ? "" : "s")",
    isSelected: isSelected,
    badgeCount: isExpanded ? nil : typeNode.brandNodes.count
)
```

**Rule:** Only show the badge when the node is **collapsed** (not expanded). When expanded, the children are visible so the badge is redundant.

## Step 3: Bigger Add Buttons

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

### 3A. Replace small text buttons with bordered pill buttons

Find the "Add Style" button (currently inside `categorySection` when expanded):

```swift
Button {
    activeSheet = .addStyle(catId)
} label: {
    Label("Add Style", systemImage: "plus")
        .font(.caption)
        .foregroundStyle(Color.accentColor)
}
.buttonStyle(.plain)
```

Replace with a larger, more visible bordered button:

```swift
Button {
    activeSheet = .addStyle(catId)
} label: {
    Label("Add Style", systemImage: "plus.circle.fill")
        .font(.subheadline)
        .fontWeight(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
        )
        .foregroundStyle(Color.accentColor)
}
.buttonStyle(.plain)
```

Apply the same pattern to the "Add Type" button inside `styleSection`.

Keep the indentation/padding the same so it aligns with its parent's children.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] All tree nodes sorted alphabetically A-Z at every level
- [ ] Count badges appear on collapsed Category (style count), Style (type count), Type (brand count) nodes
- [ ] Badges hide when node is expanded
- [ ] "Add Style" and "Add Type" buttons are visually prominent bordered pills
- [ ] Touch targets on add buttons are at least 44px tall

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14C-categories-tree-search.md`.
