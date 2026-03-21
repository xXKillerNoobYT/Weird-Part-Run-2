# Fix Prompt 13D: Catalog Page — Smart Natural Language Search Bar

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompts 13A-13C must be completed first.

---

## What the User Wants

The search bar should understand natural language queries. Instead of manually setting 5 separate filter dropdowns, the user types something like "low stock white elbows from Lutron" and the app parses it into filters automatically.

This is a **local, on-device parser** — no AI model needed for this part. It matches keywords against the known categories, styles, types, colors, and brands already loaded in memory.

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`**

### Step 1: Add a NL Parser Function

Add this function to `PartsCatalogPage`. It takes the search text and the loaded lookup data (categories, styles, types, colors, brands) and extracts any matching filters:

```swift
/// Parse natural language search text into structured filters.
///
/// Examples:
///   "low stock white elbows from Lutron"
///     → lowStock: true, color: "White", type matches "elbows", brand: "Lutron"
///   "PVC fittings"
///     → category matches "Fittings", style matches "PVC"
///   "charlotte pipe"
///     → brand: "Charlotte Pipe"
private func parseNaturalLanguageSearch(_ text: String) -> NLSearchResult {
    let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
    guard !lower.isEmpty else {
        return NLSearchResult()
    }

    var result = NLSearchResult()
    var remainingTerms: [String] = []

    // Tokenize — split on spaces, remove common filler words
    let fillerWords: Set<String> = ["from", "by", "in", "the", "a", "an", "with", "for", "all", "show", "find", "me", "get"]
    let tokens = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty && !fillerWords.contains($0) }

    // Check for "low stock" / "lowstock"
    if lower.contains("low stock") || lower.contains("lowstock") || lower.contains("low-stock") {
        result.lowStock = true
    }

    // Match tokens against known values (case-insensitive)
    var matchedTokenIndices: Set<Int> = []

    // Try to match brands (can be multi-word, so check 2-word and 1-word combos)
    for brand in brands {
        if lower.contains(brand.name.lowercased()) {
            result.brandId = brand.id
            // Mark tokens that matched
            let brandTokens = brand.name.lowercased().components(separatedBy: .whitespaces)
            for (i, token) in tokens.enumerated() {
                if brandTokens.contains(token) { matchedTokenIndices.insert(i) }
            }
            break
        }
    }

    // Match categories
    for cat in categories {
        if lower.contains(cat.name.lowercased()) {
            result.categoryId = cat.id
            let catTokens = cat.name.lowercased().components(separatedBy: .whitespaces)
            for (i, token) in tokens.enumerated() {
                if catTokens.contains(token) { matchedTokenIndices.insert(i) }
            }
            break
        }
    }

    // Match styles
    for style in styles {
        if lower.contains(style.name.lowercased()) {
            result.styleId = style.id
            let styleTokens = style.name.lowercased().components(separatedBy: .whitespaces)
            for (i, token) in tokens.enumerated() {
                if styleTokens.contains(token) { matchedTokenIndices.insert(i) }
            }
            break
        }
    }

    // Match types
    for type in types {
        if lower.contains(type.name.lowercased()) {
            result.typeId = type.id
            let typeTokens = type.name.lowercased().components(separatedBy: .whitespaces)
            for (i, token) in tokens.enumerated() {
                if typeTokens.contains(token) { matchedTokenIndices.insert(i) }
            }
            break
        }
    }

    // Match colors
    for color in colors {
        if lower.contains(color.name.lowercased()) {
            result.colorId = color.id
            let colorTokens = color.name.lowercased().components(separatedBy: .whitespaces)
            for (i, token) in tokens.enumerated() {
                if colorTokens.contains(token) { matchedTokenIndices.insert(i) }
            }
            break
        }
    }

    // Remaining unmatched tokens become the text search
    for (i, token) in tokens.enumerated() {
        if !matchedTokenIndices.contains(i) && token != "low" && token != "stock" {
            remainingTerms.append(token)
        }
    }
    result.textSearch = remainingTerms.joined(separator: " ")

    return result
}

struct NLSearchResult {
    var categoryId: Int64?
    var styleId: Int64?
    var typeId: Int64?
    var colorId: Int64?
    var brandId: Int64?
    var lowStock: Bool = false
    var textSearch: String = ""
}
```

### Step 2: Wire the Parser Into Search

Update the `.onChange(of: searchText)` handler to parse the search text and apply filters:

```swift
.onChange(of: searchText) { _, newValue in
    let trimmed = newValue.trimmingCharacters(in: .whitespaces)

    // If the text looks like a natural language query (has 2+ words or matches known terms)
    let parsed = parseNaturalLanguageSearch(trimmed)

    if parsed.hasStructuredFilters {
        // Apply parsed filters to the filter state
        selectedCategoryId = parsed.categoryId
        selectedStyleId = parsed.styleId
        selectedTypeId = parsed.typeId
        selectedColorId = parsed.colorId
        selectedBrandId = parsed.brandId
        lowStockOnly = parsed.lowStock

        // Keep only unmatched text in the SQL search
        // Don't clear searchText — keep the user's typed text visible
    }

    resetAndLoad()
}
```

Add a helper to `NLSearchResult`:

```swift
struct NLSearchResult {
    // ...existing properties...

    var hasStructuredFilters: Bool {
        categoryId != nil || styleId != nil || typeId != nil ||
        colorId != nil || brandId != nil || lowStock
    }
}
```

### Step 3: Show Active NL Filters as Visual Feedback

When the parser detects filters, show a small banner below the search bar indicating what was parsed:

```swift
@ViewBuilder
private var nlFilterBanner: some View {
    let parsed = parseNaturalLanguageSearch(searchText)
    if parsed.hasStructuredFilters {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.blue)
            Text("Smart search applied filters")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear filters") {
                clearAllFilters()
                searchText = ""
            }
            .font(.caption2)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, 4)
    }
}
```

Place it between the search bar and the filter chips in the body.

### Step 4: Update loadData to Use Parsed Text Search

In `loadData()`, the text search should use `parsed.textSearch` (the unmatched leftover) instead of the full `searchText` for the SQL LIKE query. This way, if the user types "low stock white elbows from Lutron", the SQL search is only for "elbows" (unmatched tokens) while filters handle the rest.

Modify the search clause building (around line 587-594):

```swift
let parsed = parseNaturalLanguageSearch(searchText)
let effectiveSearchText = parsed.hasStructuredFilters ? parsed.textSearch : searchText.trimmingCharacters(in: .whitespaces)

if !effectiveSearchText.isEmpty {
    whereClauses.append("(p.name LIKE ? OR p.code LIKE ? OR COALESCE(b.name, '') LIKE ?)")
    let like = "%\(effectiveSearchText)%"
    args.append(like)
    args.append(like)
    args.append(like)
}
```

---

## Success Criteria

1. Type "white" → Color filter auto-selects "White" (if that color exists)
2. Type "low stock elbows" → Low Stock filter turns on + "elbows" searches in name/code
3. Type "Lutron PVC" → Brand filter selects Lutron, Style filter selects PVC
4. Type "abc123" (no matches to known filters) → treated as plain text search (no filters applied)
5. "Smart search applied filters" banner appears when NL parsing activated filters
6. Filter chips visually update to show the auto-applied filters
7. "Clear filters" button resets everything
8. Plain single-word searches still work normally (no unintended filter matching)

---

## When Done

Read and implement **prompt 13E-catalog-ai-context.md** next.
