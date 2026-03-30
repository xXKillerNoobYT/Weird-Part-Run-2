# 62S — Extend AI Filter Activation to All Pages with Smart Card Filters
> Chain position: Standalone

## Task

Currently, AI-driven filter activation (e.g., "show me critical parts") only works on the catalog page. Extend it so that when the AI says "show critical parts," the forecasting page's critical card activates, the PO page's overdue card activates, etc. The AI needs a registry of which pages have which filter cards, and a mechanism to activate them cross-page.

### Step 1: Create a shared filter activation registry

Create a new file: `Weird Parts IOS/Weird Parts IOS/Shared/AIFilterRegistry.swift`

```swift
import SwiftUI
import Combine

/// Central registry that maps AI filter intents to page-specific filter activations.
/// Pages register their available filters on appear; the AI activates filters by intent name.
@MainActor
final class AIFilterRegistry: ObservableObject {

    struct FilterRegistration {
        let pageId: String          // e.g., "catalog", "forecasting", "purchase-orders"
        let filterName: String      // e.g., "critical", "low-stock", "overdue"
        let displayLabel: String    // e.g., "Critical Parts", "Low Stock", "Overdue POs"
        let activate: () -> Void    // Closure to activate the filter on the page
        let deactivate: () -> Void  // Closure to deactivate the filter
    }

    /// All registered filters, keyed by pageId.
    @Published private(set) var registrations: [String: [FilterRegistration]] = [:]

    /// The most recently activated filter intent (for cross-page navigation).
    @Published var pendingFilterIntent: (pageId: String, filterName: String)?

    /// Register filters for a page. Call this in .onAppear or .task.
    func register(pageId: String, filters: [FilterRegistration]) {
        registrations[pageId] = filters
    }

    /// Unregister when page disappears.
    func unregister(pageId: String) {
        registrations.removeValue(forKey: pageId)
    }

    /// Activate a filter by intent. Returns true if the filter was found and activated.
    @discardableResult
    func activateFilter(pageId: String, filterName: String) -> Bool {
        if let filters = registrations[pageId],
           let filter = filters.first(where: { $0.filterName == filterName }) {
            filter.activate()
            return true
        }
        // Page not currently loaded — store as pending
        pendingFilterIntent = (pageId: pageId, filterName: filterName)
        return false
    }

    /// Check and apply pending filter intent when a page loads.
    func applyPendingFilter(pageId: String) {
        guard let pending = pendingFilterIntent,
              pending.pageId == pageId else { return }

        if let filters = registrations[pageId],
           let filter = filters.first(where: { $0.filterName == pending.filterName }) {
            filter.activate()
            pendingFilterIntent = nil
        }
    }

    /// Get all available filter names across all pages (for AI context).
    func getAvailableFilters() -> [(pageId: String, filterName: String, displayLabel: String)] {
        registrations.flatMap { (pageId, filters) in
            filters.map { (pageId: pageId, filterName: $0.filterName, displayLabel: $0.displayLabel) }
        }
    }
}
```

### Step 2: Add the registry to AppCore

In `AppCore.swift`, add:

```swift
let aiFilterRegistry = AIFilterRegistry()
```

And pass it as an environment object in the app entry point (wherever `.environmentObject(appCore)` is set):

```swift
.environmentObject(appCore.aiFilterRegistry)
```

### Step 3: Register filters on key pages

**In PartsCatalogPage.swift** (already has smart cards), add in `.onAppear`:

```swift
@EnvironmentObject private var filterRegistry: AIFilterRegistry

// In .task or .onAppear:
filterRegistry.register(pageId: "catalog", filters: [
    .init(pageId: "catalog", filterName: "low-stock", displayLabel: "Low Stock Parts",
          activate: { self.activeFilter = .lowStock },
          deactivate: { self.activeFilter = nil }),
    .init(pageId: "catalog", filterName: "critical", displayLabel: "Critical Parts",
          activate: { self.activeFilter = .critical },
          deactivate: { self.activeFilter = nil }),
])
filterRegistry.applyPendingFilter(pageId: "catalog")

// In .onDisappear:
filterRegistry.unregister(pageId: "catalog")
```

**In PartsForecastingPage.swift:**

```swift
filterRegistry.register(pageId: "forecasting", filters: [
    .init(pageId: "forecasting", filterName: "critical", displayLabel: "Critical Forecast Items",
          activate: { self.activeCard = .critical },
          deactivate: { self.activeCard = nil }),
    .init(pageId: "forecasting", filterName: "reorder-soon", displayLabel: "Reorder Soon",
          activate: { self.activeCard = .reorderSoon },
          deactivate: { self.activeCard = nil }),
])
```

**In IOSPurchaseOrdersPage.swift:**

```swift
filterRegistry.register(pageId: "purchase-orders", filters: [
    .init(pageId: "purchase-orders", filterName: "overdue", displayLabel: "Overdue POs",
          activate: { self.activeFilter = .overdue },
          deactivate: { self.activeFilter = nil }),
    .init(pageId: "purchase-orders", filterName: "draft", displayLabel: "Draft POs",
          activate: { self.activeFilter = .draft },
          deactivate: { self.activeFilter = nil }),
])
```

Repeat for any other pages that have smart card filters.

### Step 4: Wire the AI to use the registry

In whatever AI processing component handles filter activation (likely a function that interprets AI responses and translates them to UI actions), add:

```swift
// When AI returns a filter intent:
if let filterRegistry = aiFilterRegistry {
    let activated = filterRegistry.activateFilter(
        pageId: intentPageId,
        filterName: intentFilterName
    )
    if !activated {
        // Page not loaded — navigate to it, filter will apply on load
        // Trigger navigation to the target page
    }
}
```

## Files to Modify

- **Create:** `Weird Parts IOS/Weird Parts IOS/Shared/AIFilterRegistry.swift`
- **Modify:** `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — add aiFilterRegistry property
- **Modify:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — register filters
- **Modify:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift` — register filters
- **Modify:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift` — register filters
- **Modify:** Any other page with smart card filters

## Success Criteria
- [ ] AIFilterRegistry exists and is available via @EnvironmentObject
- [ ] Pages register their available filters on appear and unregister on disappear
- [ ] AI can activate filters on any registered page, not just catalog
- [ ] If the target page isn't loaded, the intent is stored as pending and applied when the page loads
- [ ] `getAvailableFilters()` returns a complete list of all registered filter options for AI context
- [ ] No compile errors
