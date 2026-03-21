# Prompt 14A — Categories: Brand > Color Hierarchy Restructure

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Restructure the Parts hierarchy so colors nest **under brands** in both the data layer and the tree view. Currently brands and colors are flat siblings under Type. The correct hierarchy is:

```
Category > Style > Type > Brand > Color
```

Users must select a brand before they can add colors. A "None" / no-color option must always be available in every color list.

## Files to Modify

1. `core/Sources/WiredPartCore/Services/PartsService.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesEditorPanel.swift`
4. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesBrandSection.swift`
5. `Weird Parts IOS/Weird Parts IOS/Features/Parts/TypeBrandColorSection.swift`

## Step 1: Service Layer — Add BrandNode, Restructure TypeNode

**File:** `core/Sources/WiredPartCore/Services/PartsService.swift`

### 1A. Add new BrandNode struct

Find the existing `TypeNode` struct definition:

```swift
struct TypeNode: Identifiable {
    let type: PartType
    let colors: [PartColor]
    let brands: [Brand]
    var id: Int64? { type.id }
}
```

Add a new struct **before** `TypeNode`:

```swift
/// A brand node within a type, containing the colors that have catalog parts for this brand+type combination.
struct BrandNode: Identifiable {
    let brand: Brand?          // nil = "General" (no specific brand)
    let colors: [PartColor]    // colors with catalog parts for this brand+type
    let allColors: [PartColor] // all available colors for the color picker
    var id: Int64 { brand?.id ?? -1 }
    var name: String { brand?.name ?? "General" }
    var isGeneral: Bool { brand == nil }
}
```

### 1B. Update TypeNode to use BrandNode

Replace `TypeNode` with:

```swift
struct TypeNode: Identifiable {
    let type: PartType
    let brandNodes: [BrandNode]  // brands with their per-brand colors
    var id: Int64? { type.id }

    /// Convenience: all linked brand IDs (excluding General)
    var linkedBrandIds: Set<Int64> {
        Set(brandNodes.compactMap { $0.brand?.id })
    }

    /// Convenience: total color count across all brands
    var totalColorCount: Int {
        brandNodes.reduce(0) { $0 + $1.colors.count }
    }
}
```

### 1C. Update getHierarchy() to build BrandNode tree

In the `getHierarchy()` method, find where it builds `TypeNode` instances. Replace the brand/color fetching logic with:

```swift
// For each type, build BrandNode array
let typeBrandLinks = try Row.fetchAll(db, sql: """
    SELECT tbl.id AS link_id, tbl.brand_id, b.name, b.website, b.notes, b.deleted_at AS brand_deleted
    FROM type_brand_links tbl
    JOIN brands b ON b.id = tbl.brand_id
    WHERE tbl.type_id = ? AND tbl.deleted_at IS NULL AND b.deleted_at IS NULL
    ORDER BY b.name ASC
""", arguments: [typeId])

let allColors = try PartColor.fetchAll(db, sql: """
    SELECT * FROM part_colors WHERE deleted_at IS NULL ORDER BY name ASC
""")

// Build brand nodes: for each linked brand, find which colors have catalog parts
var brandNodes: [BrandNode] = []

// General (no brand) node — always present
let generalColors = try PartColor.fetchAll(db, sql: """
    SELECT DISTINCT pc.* FROM parts p
    JOIN part_colors pc ON pc.id = p.color_id
    WHERE p.type_id = ? AND p.brand_id IS NULL AND p.deleted_at IS NULL AND pc.deleted_at IS NULL
    ORDER BY pc.name ASC
""", arguments: [typeId])
brandNodes.append(BrandNode(brand: nil, colors: generalColors, allColors: allColors))

// Named brands
for row in typeBrandLinks {
    let brandId: Int64 = row["brand_id"]
    let brand = Brand(
        id: brandId,
        name: row["name"],
        website: row["website"],
        notes: row["notes"],
        deletedAt: nil,
        createdAt: nil,
        updatedAt: nil
    )
    let brandColors = try PartColor.fetchAll(db, sql: """
        SELECT DISTINCT pc.* FROM parts p
        JOIN part_colors pc ON pc.id = p.color_id
        WHERE p.type_id = ? AND p.brand_id = ? AND p.deleted_at IS NULL AND pc.deleted_at IS NULL
        ORDER BY pc.name ASC
    """, arguments: [typeId, brandId])
    brandNodes.append(BrandNode(brand: brand, colors: brandColors, allColors: allColors))
}
```

Then construct TypeNode with `brandNodes` instead of separate `brands` and `colors` arrays.

### 1D. Add getTypeBrandLinkId service method

Add this new method to PartsService (eliminates raw SQL in views):

```swift
/// Find the link row ID for a type-brand association.
func getTypeBrandLinkId(typeId: Int64, brandId: Int64) throws -> Int64? {
    try db.reader.read { db in
        try Int64.fetchOne(db, sql: """
            SELECT id FROM type_brand_links WHERE type_id = ? AND brand_id = ? AND deleted_at IS NULL
        """, arguments: [typeId, brandId])
    }
}
```

## Step 2: Update CategoriesTreeView — Brand > Color Nesting

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

### 2A. Add expandedBrands state

Add to the existing state variables:

```swift
@State private var expandedBrands: Set<Int64> = [] // brand.id, -1 = General
```

### 2B. Replace flat brand/color rows with nested structure

Find the `typeSection` method. Replace the children section (where it shows `typeNode.brands` and `typeNode.colors` as siblings) with nested Brand > Color:

```swift
// Children (brand nodes, each with their colors)
if isExpanded {
    ForEach(typeNode.brandNodes) { brandNode in
        brandSection(brandNode, typeId: typeId)
    }

    if typeNode.brandNodes.isEmpty {
        Text("No brands linked — add brands to start building catalog entries")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, DS.Space.lg * 4 + DS.Space.xl)
            .padding(.vertical, DS.Space.xs)
    }
}
```

### 2C. Add brandSection method

Add a new method after `typeSection`:

```swift
// MARK: - Brand Level (under Type)

@ViewBuilder
private func brandSection(_ brandNode: PartsService.BrandNode, typeId: Int64) -> some View {
    let brandId = brandNode.id  // -1 for General
    let isSelected = selection == .brand(brandId: brandNode.brand?.id ?? 0, typeId: typeId)
    let isExpanded = expandedBrands.contains(brandId)

    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: DS.Space.sm) {
            if !brandNode.colors.isEmpty {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            treeRow(
                icon: brandNode.isGeneral ? "circle.dashed" : "tag.fill",
                iconColor: brandNode.isGeneral ? .secondary : .orange,
                title: brandNode.name,
                subtitle: "\(brandNode.colors.count) color\(brandNode.colors.count == 1 ? "" : "s")",
                isSelected: isSelected
            )
        }
        .padding(.leading, DS.Space.lg * 3 + 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if let brand = brandNode.brand {
                selection = .brand(brandId: brand.id ?? 0, typeId: typeId)
            } else {
                selection = .brand(brandId: 0, typeId: typeId) // General
            }
            if !brandNode.colors.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedBrands.remove(brandId)
                    } else {
                        expandedBrands.insert(brandId)
                    }
                }
            }
        }

        // Color children under this brand
        if isExpanded {
            ForEach(brandNode.colors, id: \.id) { color in
                colorRow(color, typeId: typeId, brandId: brandNode.brand?.id)
            }
        }
    }
}
```

### 2D. Update colorRow to accept optional brandId

Change the `colorRow` signature and selection to include the brand:

```swift
private func colorRow(_ color: PartColor, typeId: Int64, brandId: Int64?) -> some View {
    let colorId = color.id ?? 0
    let isSelected = selection == .color(colorId: colorId, typeId: typeId, brandId: brandId)
    // ... rest stays the same but update the onTapGesture:
    .onTapGesture {
        selection = .color(colorId: colorId, typeId: typeId, brandId: brandId)
    }
}
```

### 2E. Remove old standalone brandRow method

Delete the old `brandRow(_ brand: Brand, typeId: Int64)` method since brands are now handled by `brandSection`.

## Step 3: Update CategoriesEditorPanel

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesEditorPanel.swift`

### 3A. Update typeEditor to use brandNodes

In the `typeEditor` method, the `TypeBrandColorSection` usage stays the same (it already handles brands + per-brand colors). Just make sure it compiles with the new `TypeNode` structure. If `TypeBrandColorSection` references `typeNode.brands` or `typeNode.colors`, update those to use `typeNode.brandNodes`.

### 3B. Update brandEditor

The `brandEditor` should now receive the `BrandNode` info. Update it to find the brand from `typeNode.brandNodes` instead of `typeNode.brands`:

```swift
private func brandEditor(brandId: Int64, typeId: Int64) -> some View {
    if let (_, _, typeNode) = findType(typeId) {
        let brandNode = typeNode.brandNodes.first(where: { $0.id == brandId })
        // Use brandNode.brand for display, brandNode.colors for the color list
        // ...
    }
}
```

## Step 4: Fix Raw SQL in Views

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesBrandSection.swift`
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/TypeBrandColorSection.swift`

In both files, find the `toggleBrand` method where it does direct SQL:

```swift
let linkId = try await db.writer.read { dbConn -> Int64? in
    try Int64.fetchOne(dbConn, sql: "SELECT id FROM type_brand_links WHERE type_id = ? AND brand_id = ?", ...)
}
```

Replace with the new service method:

```swift
let linkId = try service.getTypeBrandLinkId(typeId: typeId, brandId: brandId)
```

Remove any `guard let db = appCore.db else { return }` lines that were only needed for the raw SQL.

## Step 5: Ensure "None" Color Always Available

In every color picker / color list in the hierarchy, ensure there is always a "None" option. In `CategoriesColorPicker.swift`, when loading colors, check if a "None" color exists in the system. If not, the service should auto-create one during initialization or the picker should show a synthetic "None" option at the top:

```swift
// At the top of the color list, always show "None" option
let noneColor = PartColor(id: nil, name: "None", hexCode: nil, sortOrder: -1, deletedAt: nil, createdAt: nil, updatedAt: nil)
// Prepend to the colors array if no "None" color exists
if !allColors.contains(where: { $0.name.lowercased() == "none" }) {
    allColors.insert(noneColor, at: 0)
}
```

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] `PartsService.TypeNode` uses `brandNodes: [BrandNode]` instead of flat `brands` + `colors`
- [ ] Tree view shows: Category > Style > Type > Brand > Color (colors nested under brands)
- [ ] "General" brand always appears under every Type
- [ ] Must select a brand in the tree to see its colors
- [ ] "None" color option always available in color pickers
- [ ] No raw SQL in view files — all queries go through `PartsService`
- [ ] Tapping a brand in the tree selects it AND expands to show its colors
- [ ] Color picker still creates catalog parts with correct brand+type+color

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14B-categories-sort-badges-buttons.md`.
