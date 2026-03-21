# Fix Prompt 13E: Catalog Page — AI Assistant with Catalog Context

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompts 13A-13D must be completed first.

---

## What the User Wants

When the user opens the AI assistant (orange floating button) while on the Catalog page, the AI should know what page they're on, what filters are active, and be able to adjust filters or search based on conversation. The user says "show me all low stock PVC fittings" and the AI sets the filters, then the user follows up with "which ones are from Charlotte Pipe?" and the AI narrows further.

---

## Files To Edit

### 1. PartsCatalogPage.swift — Expose Filter State for AI

The AI assistant needs to know the current catalog state (active filters, search text, result count) and be able to **set** filters programmatically.

Add a `CatalogContext` struct that captures the current state:

```swift
/// Current catalog page state for AI context.
struct CatalogContext {
    let activeFilters: [String: String] // e.g. ["category": "Fittings", "brand": "Lutron"]
    let searchText: String
    let resultCount: Int
    let lowStockOnly: Bool

    var description: String {
        var parts: [String] = []
        if !searchText.isEmpty { parts.append("searching for '\(searchText)'") }
        for (key, value) in activeFilters {
            parts.append("\(key): \(value)")
        }
        if lowStockOnly { parts.append("low stock only") }
        parts.append("\(resultCount) parts found")
        return parts.isEmpty ? "Showing all parts" : parts.joined(separator: ", ")
    }
}
```

Add a method to build the current context:

```swift
private var currentCatalogContext: CatalogContext {
    var filters: [String: String] = [:]
    if let catId = selectedCategoryId,
       let name = categories.first(where: { $0.id == catId })?.name {
        filters["category"] = name
    }
    if let styleId = selectedStyleId,
       let name = styles.first(where: { $0.id == styleId })?.name {
        filters["style"] = name
    }
    if let typeId = selectedTypeId,
       let name = types.first(where: { $0.id == typeId })?.name {
        filters["type"] = name
    }
    if let colorId = selectedColorId,
       let name = colors.first(where: { $0.id == colorId })?.name {
        filters["color"] = name
    }
    if let brandId = selectedBrandId,
       let name = brands.first(where: { $0.id == brandId })?.name {
        filters["brand"] = name
    }

    return CatalogContext(
        activeFilters: filters,
        searchText: searchText,
        resultCount: totalCount,
        lowStockOnly: lowStockOnly
    )
}
```

### 2. Post Catalog Context When AI Opens

When the user opens the AI assistant from the catalog page, send the context. Use `NotificationCenter` to pass the current page context:

```swift
// Add to PartsCatalogPage body, notification when page is visible:
.onAppear {
    NotificationCenter.default.post(
        name: .catalogPageActive,
        object: nil,
        userInfo: [
            "context": currentCatalogContext.description,
            "availableCategories": categories.map(\.name),
            "availableBrands": brands.map(\.name),
            "availableColors": colors.map(\.name)
        ]
    )
}
.onDisappear {
    NotificationCenter.default.post(name: .catalogPageInactive, object: nil)
}
```

Add the notification names:

```swift
extension Notification.Name {
    static let catalogPageActive = Notification.Name("catalogPageActive")
    static let catalogPageInactive = Notification.Name("catalogPageInactive")
}
```

### 3. Listen for AI Filter Commands

The AI assistant can send filter commands back to the catalog page. Listen for them:

```swift
.onReceive(NotificationCenter.default.publisher(for: .aiSetCatalogFilters)) { notification in
    if let userInfo = notification.userInfo {
        // Apply filters from AI
        if let categoryName = userInfo["category"] as? String {
            selectedCategoryId = categories.first(where: {
                $0.name.lowercased() == categoryName.lowercased()
            })?.id
        }
        if let brandName = userInfo["brand"] as? String {
            selectedBrandId = brands.first(where: {
                $0.name.lowercased() == brandName.lowercased()
            })?.id
        }
        if let colorName = userInfo["color"] as? String {
            selectedColorId = colors.first(where: {
                $0.name.lowercased() == colorName.lowercased()
            })?.id
        }
        if let search = userInfo["search"] as? String {
            searchText = search
        }
        if let lowStock = userInfo["lowStock"] as? Bool {
            lowStockOnly = lowStock
        }
        if let clearAll = userInfo["clearAll"] as? Bool, clearAll {
            clearAllFilters()
        }

        resetAndLoad()
    }
}
```

Add the notification name:

```swift
extension Notification.Name {
    static let aiSetCatalogFilters = Notification.Name("aiSetCatalogFilters")
}
```

### 4. IOSAIAssistantPanel.swift — Send Filter Commands

**File:** `Weird Parts IOS/AI/IOSAIAssistantPanel.swift`

When the AI panel is open and receives a catalog context, include it in the system prompt for Foundation Models. When the AI's response includes a filter instruction, post the notification.

In the AI panel, add a catalog context listener:

```swift
@State private var catalogContext: String?

// Listen for catalog context:
.onReceive(NotificationCenter.default.publisher(for: .catalogPageActive)) { notification in
    if let context = notification.userInfo?["context"] as? String {
        catalogContext = context
    }
}
.onReceive(NotificationCenter.default.publisher(for: .catalogPageInactive)) { _ in
    catalogContext = nil
}
```

When building the AI prompt, include the context:

```swift
// In the method that sends queries to Foundation Models:
var systemContext = "You are a parts catalog assistant for WiredPart."
if let ctx = catalogContext {
    systemContext += " The user is on the Parts Catalog page. Current state: \(ctx)"
    systemContext += " You can set filters by responding with a JSON action block."
}
```

When the AI responds with a filter action, parse and post it:

```swift
// If AI response contains a filter command (parsed from structured response):
// Post it to the catalog page
func applyAIFilterCommand(_ filters: [String: Any]) {
    NotificationCenter.default.post(
        name: .aiSetCatalogFilters,
        object: nil,
        userInfo: filters
    )
}
```

**Note:** The exact implementation depends on how Foundation Models tool calling works in your `FoundationModelsService`. The key pattern is:
1. AI receives catalog context in its system prompt
2. AI can respond with structured filter actions
3. Those actions are posted via NotificationCenter to the catalog page
4. The catalog page applies the filters and reloads

---

## Success Criteria

1. Open AI assistant while on Catalog page → AI knows what filters are active and how many parts are showing
2. Say "show me low stock parts" → AI sets lowStockOnly=true, catalog updates
3. Say "filter by Lutron" → AI sets brand filter, catalog updates
4. Say "clear all filters" → AI clears everything, catalog shows all parts
5. Say "how many PVC fittings do we have?" → AI sets Category + Style filters, reports the count
6. Follow-up "which are low stock?" → AI adds lowStockOnly without losing previous filters
7. When user navigates AWAY from catalog, AI stops sending catalog-specific commands

---

## All Catalog Prompts (13A-13E) Complete

After all 5 are done, the Catalog page will have:
- **Fixed search bar** always visible at top
- **Always-visible filter chips** with no toggle
- **Working detail sheet** with stock locations and edit button
- **Smart NL search** that parses "low stock white elbows from Lutron" into filters
- **AI integration** that can read and control catalog filters via conversation
