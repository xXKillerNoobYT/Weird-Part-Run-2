# 16H — Catalog Page Pricing Integration + Multiple View Modes

> **Chain position:** 16A–16G → **16H** → 16I (AI)
> **Prerequisite:** 16G complete (stale alerts, receiving verification)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Two features:

1. **Catalog Page Pricing Integration:** The Parts Catalog page should let users see and quick-edit pricing inline, so they can visualize prices in context with the part hierarchy, stock levels, and other details.

2. **Multiple View Modes for Pricing Page:** Give users 3 different ways to view the pricing data so they can pick the layout they prefer:
   - **List View** (default — current) — compact rows with tier badges
   - **Card View** — larger cards showing more pricing detail per part
   - **Table View** — spreadsheet-style with columns for cost, markup, margin, sell, tier

**Key files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsPricingPage.swift` (add view mode toggle)
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` (add pricing column/overlay)

## Task

### Step 1: Add view mode toggle to PartsPricingPage.swift

Add a new enum and state variable:

```swift
private enum PricingViewMode: String, CaseIterable {
    case list = "List"
    case cards = "Cards"
    case table = "Table"

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .cards: return "square.grid.2x2"
        case .table: return "tablecells"
        }
    }
}

@State private var viewMode: PricingViewMode = .list
```

Add a view mode picker in the toolbar (before the ellipsis menu):

```swift
ToolbarItem(placement: .secondaryAction) {
    Picker("View", selection: $viewMode) {
        ForEach(PricingViewMode.allCases, id: \.self) { mode in
            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: 200)
}
```

Or if toolbar space is tight, use a menu:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Menu {
        Picker("View Mode", selection: $viewMode) {
            ForEach(PricingViewMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
            }
        }
    } label: {
        Image(systemName: viewMode.icon)
    }
}
```

Replace the content area to switch on viewMode:

```swift
if isLoading {
    ProgressView("Loading pricing...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else if let error = loadError {
    ErrorStateView(message: error) { Task { await loadData() } }
} else if sortedParts.isEmpty {
    emptyState
} else {
    switch viewMode {
    case .list: pricingListView
    case .cards: pricingCardsView
    case .table: pricingTableView
    }
}
```

### Step 2: Card View

```swift
@ViewBuilder
private var pricingCardsView: some View {
    ScrollView {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
        ], spacing: 12) {
            ForEach(sortedParts) { row in
                Button {
                    activeSheet = .editPart(row)
                } label: {
                    pricingCard(row)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

@ViewBuilder
private func pricingCard(_ row: PricingDisplayRow) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        // Header: name + tier badge
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    if row.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let code = row.code {
                    Text(code)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            tierBadge(row.tierLevel, isInherited: row.isInherited)
        }

        Divider()

        // Price details in a 2×2 grid
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Avg Cost")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatPrice(row.weightedAvgCost))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Sell Price")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatPrice(row.sellPrice))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        }

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pricingMode == "markup" ? "Markup" : "Margin")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f%%", pricingMode == "markup" ? row.effectiveMarkup : row.effectiveMargin))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Profit/Unit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let profit = row.sellPrice - row.weightedAvgCost
                Text(formatPrice(profit))
                    .font(.subheadline)
                    .foregroundStyle(profit > 0 ? Color.accentColor : .red)
            }
        }
    }
    .padding()
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(row.isStale ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
    )
}
```

### Step 3: Table View

```swift
@ViewBuilder
private var pricingTableView: some View {
    ScrollView(.horizontal, showsIndicators: true) {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                tableHeader("Part Name", width: 180)
                tableHeader("Avg Cost", width: 90)
                tableHeader("Markup %", width: 80)
                tableHeader("Margin %", width: 80)
                tableHeader("Sell Price", width: 90)
                tableHeader("Profit", width: 80)
                tableHeader("Source", width: 100)
            }
            .background(Color(.tertiarySystemGroupedBackground))

            Divider()

            // Data rows
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(sortedParts) { row in
                        Button {
                            activeSheet = .editPart(row)
                        } label: {
                            HStack(spacing: 0) {
                                // Part name
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    if let code = row.code {
                                        Text(code)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 180, alignment: .leading)
                                .padding(.horizontal, 6)

                                // Avg cost
                                Text(String(format: "$%.2f", row.weightedAvgCost))
                                    .font(.caption)
                                    .monospaced()
                                    .frame(width: 90, alignment: .trailing)
                                    .padding(.horizontal, 4)

                                // Markup
                                Text(String(format: "%.1f%%", row.effectiveMarkup))
                                    .font(.caption)
                                    .monospaced()
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.horizontal, 4)

                                // Margin
                                Text(String(format: "%.1f%%", row.effectiveMargin))
                                    .font(.caption)
                                    .monospaced()
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.horizontal, 4)

                                // Sell price
                                Text(String(format: "$%.2f", row.sellPrice))
                                    .font(.caption)
                                    .monospaced()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                    .frame(width: 90, alignment: .trailing)
                                    .padding(.horizontal, 4)

                                // Profit
                                let profit = row.sellPrice - row.weightedAvgCost
                                Text(String(format: "$%.2f", profit))
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(profit > 0 ? Color.accentColor : .red)
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.horizontal, 4)

                                // Source tier
                                tierBadge(row.tierLevel, isInherited: row.isInherited)
                                    .frame(width: 100, alignment: .center)
                            }
                            .frame(minHeight: 40)
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
            }
        }
    }
}

@ViewBuilder
private func tableHeader(_ title: String, width: CGFloat) -> some View {
    Text(title)
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .frame(width: width, alignment: title == "Part Name" ? .leading : .trailing)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
}
```

### Step 4: Add pricing overlay to PartsCatalogPage

In `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`, find the part card/row view and add a pricing info line.

Add a state variable:

```swift
@State private var showPricing = false
```

Add a toggle in the toolbar or filter area:

```swift
Button {
    showPricing.toggle()
} label: {
    Label(showPricing ? "Hide Prices" : "Show Prices", systemImage: showPricing ? "dollarsign.circle.fill" : "dollarsign.circle")
        .font(.caption)
}
```

In each part card/row, conditionally show pricing info:

```swift
if showPricing {
    HStack(spacing: 8) {
        // These values would need to be loaded — either precompute during loadData()
        // or add a lightweight pricing lookup
        if let pricing = partPricingCache[part.id ?? 0] {
            Text(String(format: "Cost: $%.2f", pricing.weightedAvgCost))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "Sell: $%.2f", pricing.sellPrice))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.green)
            Text(String(format: "+%.0f%%", pricing.effectiveMarkup))
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
```

Add a pricing cache to the page:

```swift
@State private var partPricingCache: [Int64: PartsService.ResolvedPricing] = [:]
```

In `loadData()`, when `showPricing` is true, load pricing for displayed parts:

```swift
if showPricing, let service = appCore.partsService {
    var cache: [Int64: PartsService.ResolvedPricing] = [:]
    for part in displayedParts {
        guard let partId = part.id else { continue }
        if let resolved = try? service.resolvePartPricing(partId: partId) {
            cache[partId] = resolved
        }
    }
    partPricingCache = cache
}
```

Also add `.onChange(of: showPricing)` to trigger reload:

```swift
.onChange(of: showPricing) { Task { await loadData() } }
```

### Step 5: Quick-edit from catalog

When a user taps the pricing info on a catalog part (when showPricing is on), open the same `PricingEditSheet` from 16D. Add the sheet case:

```swift
// In catalog page's active sheet enum, add:
case editPricing(PricingDisplayRow)

// In sheet handler:
case .editPricing(let row):
    PricingEditSheet(row: row, pricingMode: pricingMode) { await loadData() }
```

When tapping the pricing overlay:

```swift
if showPricing, let pricing = partPricingCache[part.id ?? 0] {
    Button {
        let displayRow = PricingDisplayRow(
            id: part.id ?? 0,
            name: part.name,
            code: part.code,
            categoryName: "",
            weightedAvgCost: pricing.weightedAvgCost,
            effectiveMarkup: pricing.effectiveMarkup,
            effectiveMargin: pricing.effectiveMargin,
            sellPrice: pricing.sellPrice,
            tierLevel: pricing.tierLevel,
            isInherited: pricing.isInherited,
            costLastUpdated: nil,
            isStale: false
        )
        activeSheet = .editPricing(displayRow)
    } label: {
        // pricing info HStack from above
    }
}
```

## Important Notes

- The `PricingDisplayRow` struct needs to be accessible from both files. If it's declared `private`, move it to a shared location or make it `internal`.
- For the table view, the horizontal scroll allows seeing all columns on iPhone. Make sure the outer container doesn't clip.
- Loading pricing for all visible parts on the catalog page could be slow. Consider limiting to the first 50 visible parts or using lazy loading.
- The view mode picker saves in-memory only (resets on page reload). To persist, you could save to UserDefaults, but that's optional.

## Success Criteria

- [ ] Three view modes on pricing page: List (default), Cards, Table
- [ ] View mode toggle in toolbar — switches instantly
- [ ] Card view shows: name, code, avg cost, sell price, markup/margin, profit, tier badge, stale indicator
- [ ] Table view shows: spreadsheet-style with all columns, horizontally scrollable
- [ ] List view is the existing list from 16D (unchanged)
- [ ] Catalog page has "Show Prices" toggle
- [ ] When prices shown: cost, sell price, markup % visible on each part
- [ ] Tapping pricing info on catalog opens PricingEditSheet
- [ ] No performance issues (lazy loading, limited cache)
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16H Results (YYYY-MM-DD)
- 3 view modes: list, cards, table with toolbar toggle
- Card view: 2×2 pricing grid with tier badge and stale border
- Table view: horizontal scroll spreadsheet with all pricing columns
- Catalog page: Show Prices toggle, pricing overlay, quick-edit sheet
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16I.**
