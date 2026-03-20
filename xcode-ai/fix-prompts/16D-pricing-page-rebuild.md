# 16D — Pricing Page UI Rebuild

> **Chain position:** 16A → 16B → 16C → **16D** → 16E (override flow) → 16F–16I
> **Prerequisite:** 16A–16C complete (pricing_tiers, FIFO engine, hierarchical pricing service)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The current `PartsPricingPage.swift` (389 lines) uses raw SQL, has a flat list of parts, and simple cost+markup editing. It needs a full rebuild to support hierarchical pricing, FIFO cost display, tier-level indicators, and better search/filtering.

The page should show parts grouped or filterable by their hierarchy position, with clear visual indicators of WHERE a price comes from (parent tier vs direct override).

**Key file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsPricingPage.swift`

## Task

Rewrite `PartsPricingPage.swift` completely. Remove ALL raw SQL — use only PartsService methods.

### New PartsPricingPage structure:

```swift
import SwiftUI
import WiredPartCore

struct PartsPricingPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var pricingRows: [PricingDisplayRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var sortBy: PricingSortOption = .name
    @State private var filterCategory: Int64? = nil
    @State private var categories: [PartCategory] = []
    @State private var pricingMode: String = "markup" // "markup" or "margin"
    @State private var activeSheet: PricingActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar

            // Sort chips
            sortChips

            // Content
            if isLoading {
                ProgressView("Loading pricing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if sortedParts.isEmpty {
                emptyState
            } else {
                pricingList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts by name or code...")
        .refreshable { await loadData() }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        activeSheet = .bulkEdit
                    } label: {
                        Label("Bulk Edit Markup", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        activeSheet = .pricingSettings
                    } label: {
                        Label("Pricing Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .background(DS.Background.page)
        .task { await loadData() }
    }
}
```

### PricingDisplayRow — replaces old PricingRow

```swift
struct PricingDisplayRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let categoryName: String
    let weightedAvgCost: Double
    let effectiveMarkup: Double
    let effectiveMargin: Double
    let sellPrice: Double
    let tierLevel: String       // "Part", "Brand", "Type", "Style", "Category", "Default"
    let isInherited: Bool       // true = price from parent, false = directly set
    let costLastUpdated: String?
    let isStale: Bool           // true if > 90 days since last cost update
}
```

### Filter bar — category picker + pricing mode indicator

```swift
@ViewBuilder
private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // Category filter
            Menu {
                Button("All Categories") { filterCategory = nil }
                Divider()
                ForEach(categories, id: \.id) { cat in
                    Button(cat.name) { filterCategory = cat.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterCategory == nil ? "All Categories" : categories.first(where: { $0.id == filterCategory })?.name ?? "Category")
                        .lineLimit(1)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filterCategory != nil ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(filterCategory != nil ? .white : .primary)
                .clipShape(Capsule())
            }

            Spacer()

            // Pricing mode badge
            Text(pricingMode == "markup" ? "Markup Mode" : "Margin Mode")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
    .background(Color(.secondarySystemGroupedBackground))
}
```

### Sort chips — same pattern but add "Tier" option

```swift
private enum PricingSortOption: CaseIterable {
    case name, costAsc, costDesc, markupDesc, sellDesc, tierLevel

    var label: String {
        switch self {
        case .name: return "Name"
        case .costAsc: return "Cost ↑"
        case .costDesc: return "Cost ↓"
        case .markupDesc: return "Markup ↓"
        case .sellDesc: return "Sell ↓"
        case .tierLevel: return "Tier"
        }
    }
}
```

### Pricing list — each row shows tier badge

```swift
@ViewBuilder
private var pricingList: some View {
    List {
        Section {
            Text("\(sortedParts.count) part\(sortedParts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(sortedParts) { row in
            Button {
                activeSheet = .editPart(row)
            } label: {
                pricingRowView(row)
            }
            .buttonStyle(.plain)
        }
    }
    .listStyle(.insetGrouped)
}

@ViewBuilder
private func pricingRowView(_ row: PricingDisplayRow) -> some View {
    HStack(spacing: 12) {
        // Left: name + code + tier badge
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if row.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                if let code = row.code {
                    Text(code)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                tierBadge(row.tierLevel, isInherited: row.isInherited)
            }
        }

        Spacer()

        // Right: pricing info
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Text("Avg:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatPrice(row.weightedAvgCost))
                    .font(.subheadline)
            }
            HStack(spacing: 4) {
                Text("Sell:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatPrice(row.sellPrice))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
            // Show primary mode value (markup or margin)
            if pricingMode == "markup" {
                Text(String(format: "+%.1f%% markup", row.effectiveMarkup))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Text(String(format: "%.1f%% margin", row.effectiveMargin))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
        }

        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    .frame(minHeight: 56)
}
```

### Tier badge — shows where price comes from

```swift
@ViewBuilder
private func tierBadge(_ level: String, isInherited: Bool) -> some View {
    HStack(spacing: 2) {
        if isInherited {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 8))
        }
        Text(isInherited ? "from \(level)" : level)
    }
    .font(.system(size: 9))
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(isInherited ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
    .foregroundStyle(isInherited ? .orange : .green)
    .clipShape(Capsule())
}
```

### Data loading — use PartsService, no raw SQL

```swift
@Sendable
private func loadData() async {
    isLoading = true
    loadError = nil
    do {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }

        // Load categories for filter
        let cats = try service.listCategories()

        // Load pricing mode
        let mode = try service.getCompanyCostSetting(key: "pricing_mode") ?? "markup"
        let thresholdDays = Int(try service.getCompanyCostSetting(key: "stale_price_threshold_days") ?? "90") ?? 90

        // Load all parts with resolved pricing
        let parts = try service.listParts(categoryId: filterCategory)
        var rows: [PricingDisplayRow] = []

        for part in parts {
            guard let partId = part.id else { continue }
            let resolved = try service.resolvePartPricing(partId: partId)

            // Check if stale
            let isStale: Bool
            if let lastUpdated = part.costLastUpdated,
               let date = ISO8601DateFormatter().date(from: lastUpdated) {
                isStale = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0 > thresholdDays
            } else {
                isStale = part.costLastUpdated == nil
            }

            rows.append(PricingDisplayRow(
                id: partId,
                name: part.name,
                code: part.code,
                categoryName: "", // filled below if needed
                weightedAvgCost: resolved.weightedAvgCost,
                effectiveMarkup: resolved.effectiveMarkup,
                effectiveMargin: resolved.effectiveMargin,
                sellPrice: resolved.sellPrice,
                tierLevel: resolved.tierLevel,
                isInherited: resolved.isInherited,
                costLastUpdated: part.costLastUpdated,
                isStale: isStale
            ))
        }

        await MainActor.run {
            categories = cats
            pricingMode = mode
            pricingRows = rows
            isLoading = false
        }
    } catch {
        await MainActor.run {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
```

### Sheet handling — single .sheet(item:) pattern

```swift
private enum PricingActiveSheet: Identifiable {
    case editPart(PricingDisplayRow)
    case bulkEdit
    case pricingSettings

    var id: String {
        switch self {
        case .editPart(let row): return "edit-\(row.id)"
        case .bulkEdit: return "bulk"
        case .pricingSettings: return "settings"
        }
    }
}

@ViewBuilder
private func sheetContent(_ sheet: PricingActiveSheet) -> some View {
    switch sheet {
    case .editPart(let row):
        PricingEditSheet(row: row, pricingMode: pricingMode) { await loadData() }
    case .bulkEdit:
        // Placeholder — prompt 16F builds this
        NavigationStack {
            Text("Bulk Edit — coming in next prompt")
                .navigationTitle("Bulk Edit")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { activeSheet = nil }
                    }
                }
        }
    case .pricingSettings:
        // Placeholder — prompt 16F builds this
        NavigationStack {
            Text("Pricing Settings — coming in next prompt")
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { activeSheet = nil }
                    }
                }
        }
    }
}
```

### Helper

```swift
private func formatPrice(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

private var sortedParts: [PricingDisplayRow] {
    var result = pricingRows

    if !searchText.isEmpty {
        let query = searchText.lowercased()
        result = result.filter {
            $0.name.lowercased().contains(query) ||
            ($0.code?.lowercased().contains(query) ?? false)
        }
    }

    switch sortBy {
    case .name: result.sort { $0.name.lowercased() < $1.name.lowercased() }
    case .costAsc: result.sort { $0.weightedAvgCost < $1.weightedAvgCost }
    case .costDesc: result.sort { $0.weightedAvgCost > $1.weightedAvgCost }
    case .markupDesc: result.sort { $0.effectiveMarkup > $1.effectiveMarkup }
    case .sellDesc: result.sort { $0.sellPrice > $1.sellPrice }
    case .tierLevel: result.sort { $0.tierLevel < $1.tierLevel }
    }

    return result
}

private var emptyState: some View {
    VStack(spacing: 16) {
        Image(systemName: "dollarsign.circle")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
        Text("No Pricing Data")
            .font(.title3)
            .fontWeight(.semibold)
        Text("Add parts to the catalog to manage pricing.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

### PricingEditSheet — rebuilt for hierarchy awareness

Replace the existing `PricingEditSheet` with this version that shows:
- Where the price comes from (tier badge)
- Weighted average cost from FIFO batches
- Both markup AND margin (primary is editable, secondary is calculated)
- Price history
- Cost layer breakdown (batches)

```swift
private struct PricingEditSheet: View {
    let row: PricingDisplayRow
    let pricingMode: String
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var markupText = ""
    @State private var marginText = ""
    @State private var fixedPriceText = ""
    @State private var useFixedPrice = false
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var costLayers: [CostLayer] = []
    @State private var priceHistory: [PriceHistory] = []

    private var previewSellPrice: Double {
        if useFixedPrice, let fixed = Double(fixedPriceText), fixed > 0 {
            return max(fixed, row.weightedAvgCost) // never below cost
        }
        let markup = Double(markupText) ?? 0
        return row.weightedAvgCost * (1 + max(markup, 0) / 100)
    }

    private var previewMargin: Double {
        let sell = previewSellPrice
        guard sell > 0 else { return 0 }
        return ((sell - row.weightedAvgCost) / sell) * 100
    }

    private var previewMarkup: Double {
        guard row.weightedAvgCost > 0 else { return 0 }
        return ((previewSellPrice - row.weightedAvgCost) / row.weightedAvgCost) * 100
    }

    var body: some View {
        NavigationStack {
            Form {
                // Part info
                Section("Part") {
                    LabeledContent("Name", value: row.name)
                    if let code = row.code {
                        LabeledContent("Code", value: code)
                    }
                    HStack {
                        Text("Price Source")
                        Spacer()
                        tierBadge(row.tierLevel, isInherited: row.isInherited)
                    }
                }

                // Weighted average cost (read-only)
                Section("Cost (from FIFO batches)") {
                    LabeledContent("Weighted Avg Cost") {
                        Text(String(format: "$%.5f", row.weightedAvgCost))
                            .fontWeight(.medium)
                    }
                    if !costLayers.isEmpty {
                        DisclosureGroup("Cost Layers (\(costLayers.count) batches)") {
                            ForEach(costLayers, id: \.id) { layer in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(layer.remainingQty)/\(layer.originalQty) remaining")
                                            .font(.caption)
                                        if let date = layer.purchaseDate {
                                            Text(date.prefix(10))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(String(format: "$%.5f/ea", layer.unitCost))
                                        .font(.caption)
                                        .monospaced()
                                }
                            }
                        }
                    }
                }

                // Pricing inputs
                Section("Set Price for This Part") {
                    Toggle("Use Fixed Sell Price", isOn: $useFixedPrice.animation())

                    if useFixedPrice {
                        HStack {
                            Text("Fixed Price")
                            Spacer()
                            Text("$")
                            TextField("0.00", text: $fixedPriceText)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                                .keyboardType(.decimalPad)
                        }
                        .frame(minHeight: 44)
                    } else {
                        // Primary input based on company mode
                        if pricingMode == "markup" {
                            HStack {
                                Text("Markup")
                                Spacer()
                                TextField("0", text: $markupText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                                    .keyboardType(.decimalPad)
                                Text("%")
                            }
                            .frame(minHeight: 44)

                            // Calculated margin (read-only)
                            LabeledContent("Margin (calculated)") {
                                Text(String(format: "%.1f%%", previewMargin))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Text("Margin")
                                Spacer()
                                TextField("0", text: $marginText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                                    .keyboardType(.decimalPad)
                                Text("%")
                            }
                            .frame(minHeight: 44)

                            // Calculated markup (read-only)
                            LabeledContent("Markup (calculated)") {
                                Text(String(format: "%.1f%%", previewMarkup))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Preview
                Section("Preview") {
                    LabeledContent("Sell Price") {
                        Text(String(format: "$%.2f", previewSellPrice))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    LabeledContent("Profit per Unit") {
                        let profit = previewSellPrice - row.weightedAvgCost
                        Text(String(format: "$%.2f", profit))
                            .foregroundStyle(profit > 0 ? Color.accentColor : .red)
                    }
                }

                // Price history
                if !priceHistory.isEmpty {
                    Section("Recent Price Changes") {
                        ForEach(priceHistory.prefix(5), id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.changeType.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if let date = entry.createdAt {
                                        Text(date.prefix(10))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let oldVal = entry.oldValue, let newVal = entry.newValue {
                                    Text(String(format: "$%.2f → $%.2f", oldVal, newVal))
                                        .font(.caption)
                                        .monospaced()
                                }
                            }
                        }
                    }
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Pricing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                markupText = String(format: "%.1f", row.effectiveMarkup)
                marginText = String(format: "%.1f", row.effectiveMargin)
            }
            .task { await loadDetails() }
        }
    }

    @ViewBuilder
    private func tierBadge(_ level: String, isInherited: Bool) -> some View {
        HStack(spacing: 2) {
            if isInherited {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8))
            }
            Text(isInherited ? "from \(level)" : level)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(isInherited ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
        .foregroundStyle(isInherited ? .orange : .green)
        .clipShape(Capsule())
    }

    private func loadDetails() async {
        guard let service = appCore.partsService else { return }
        do {
            costLayers = try service.getCostLayers(partId: row.id, nonEmptyOnly: true)
            priceHistory = try service.getPriceHistory(partId: row.id, limit: 10)
        } catch {
            print("[PricingEditSheet] Load details error: \(error)")
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                isSaving = false
                return
            }

            if useFixedPrice {
                let fixed = Double(fixedPriceText) ?? 0
                try service.setPricingTier(partId: row.id, fixedSellPrice: max(fixed, row.weightedAvgCost))
            } else if pricingMode == "markup" {
                let markup = max(Double(markupText) ?? 0, 0)
                try service.setPricingTier(partId: row.id, markupPercent: markup)
            } else {
                let margin = max(Double(marginText) ?? 0, 0)
                try service.setPricingTier(partId: row.id, marginPercent: margin)
            }

            // Log the change
            try service.logPriceChange(
                partId: row.id,
                changeType: "markup_change",
                oldValue: row.effectiveMarkup,
                newValue: Double(markupText) ?? row.effectiveMarkup,
                oldSellPrice: row.sellPrice,
                newSellPrice: previewSellPrice,
                source: "manual"
            )

            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

## Important Notes

- Remove `import GRDB` from this file — all data access goes through PartsService
- Remove the old `PricingRow` struct — replaced by `PricingDisplayRow`
- The old `PricingEditSheet` is replaced completely
- The sort chips view builder (`sortChips`) should use the same pattern as the existing one — just add the `.tierLevel` case
- Cost display shows up to 5 decimal places (`$%.5f`) since unit costs can be $0.00001
- Sell price preview enforces minimum at cost (never negative margin)
- Stale indicator (orange triangle) shows when `cost_last_updated` is > 90 days old or nil

## Success Criteria

- [ ] No `import GRDB` in the file
- [ ] No raw SQL anywhere — all data via PartsService
- [ ] Each part row shows: name, code, tier badge (where price comes from), avg cost, sell price, markup/margin
- [ ] Tier badge shows "from Category" (orange, inherited) vs "Part" (green, direct)
- [ ] Stale price warning icon on parts not updated in 90+ days
- [ ] Category filter dropdown works
- [ ] Edit sheet shows cost layers, price history, markup/margin based on company mode
- [ ] Save creates a pricing tier at Part level and logs the change
- [ ] `.sheet(item:)` pattern with enum — no nested sheets
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16D Results (YYYY-MM-DD)
- Full rewrite of PartsPricingPage.swift (raw SQL removed, GRDB import removed)
- New: PricingDisplayRow, PricingActiveSheet enum, tier badges, category filter
- PricingEditSheet rebuilt: cost layers, price history, markup/margin toggle
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16E.**
