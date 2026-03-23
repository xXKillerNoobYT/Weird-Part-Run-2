import SwiftUI
import WiredPartCore

/// Pricing management page showing parts with their cost, markup, and sell prices.
///
/// Displays a sortable, filterable list of parts with hierarchical pricing details.
/// Each row shows where the price comes from (tier badge), weighted average cost,
/// and sell price. Supports category filtering and multiple sort options.
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
    @State private var viewMode: PricingViewMode = .list

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
                switch viewMode {
                case .list: pricingList
                case .cards: pricingCardsView
                case .table: pricingTableView
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search parts by name or code...")
        .refreshable { await loadData() }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .toolbar {
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
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        activeSheet = .setTierPricing
                    } label: {
                        Label("Set Tier Pricing", systemImage: "square.stack.3d.up")
                    }
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
        .onAppear { postPricingContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .pricingPageInactive, object: nil)
        }
    }

    // MARK: - Filter Bar

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

    // MARK: - Sort Chips

    @ViewBuilder
    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Sort:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(PricingSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation { sortBy = option }
                    } label: {
                        Text(option.label)
                            .font(.subheadline)
                            .fontWeight(sortBy == option ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(sortBy == option ? Color.accentColor : Color.clear)
                            .foregroundStyle(sortBy == option ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Sort & Filter

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

    // MARK: - Pricing List

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

    // MARK: - Card View

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

    // MARK: - Table View

    @ViewBuilder
    private var pricingTableView: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    tableHeader("Part Name", width: 180, leading: true)
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
    private func tableHeader(_ title: String, width: CGFloat, leading: Bool = false) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: leading ? .leading : .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
    }

    // MARK: - Tier Badge

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

    // MARK: - Empty State

    @ViewBuilder
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

    // MARK: - Sheet Handling

    @ViewBuilder
    private func sheetContent(_ sheet: PricingActiveSheet) -> some View {
        switch sheet {
        case .editPart(let row):
            PricingEditSheet(row: row, pricingMode: pricingMode) { await loadData() }
        case .setTierPricing:
            PricingTierSetSheet { await loadData() }
        case .bulkEdit:
            PricingBulkEditSheet { await loadData() }
        case .pricingSettings:
            PricingSettingsSheet { await loadData() }
        case .help:
            PageHelpSheet(
                title: "Pricing Help",
                sections: [
                    ("Overview", "View and manage pricing for all parts. See cost, markup percentage, and sell price at a glance. Tier badges show where each price comes from."),
                    ("Editing", "Tap a part to edit its pricing. Use the menu for bulk edits, tier pricing setup, or global pricing settings."),
                    ("Views", "Switch between List, Cards, and Table views using the view mode icon. Filter by category and sort by name, cost, or margin.")
                ]
            )
        }
    }

    // MARK: - Data Loading

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

            // Load pricing mode and stale threshold
            let mode = try service.getCompanyCostSetting(key: "pricing_mode") ?? "markup"
            let thresholdDays = Int(try service.getCompanyCostSetting(key: "stale_price_threshold_days") ?? "90") ?? 90

            // Load all parts with resolved pricing
            let parts = try service.listParts(categoryId: filterCategory, limit: 10000)
            var rows: [PricingDisplayRow] = []

            for pwd in parts {
                guard let partId = pwd.part.id else { continue }
                let resolved = try service.resolvePartPricing(partId: partId)

                // Check if stale (cost not updated in > threshold days, or never updated)
                let isStale: Bool
                if let lastUpdated = pwd.part.costLastUpdated,
                   let date = ISO8601DateFormatter().date(from: lastUpdated) {
                    isStale = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0 > thresholdDays
                } else {
                    isStale = pwd.part.costLastUpdated == nil
                }

                rows.append(PricingDisplayRow(
                    id: partId,
                    name: pwd.part.name,
                    code: pwd.part.code,
                    categoryName: pwd.categoryName ?? "",
                    weightedAvgCost: resolved.weightedAvgCost,
                    effectiveMarkup: resolved.effectiveMarkup,
                    effectiveMargin: resolved.effectiveMargin,
                    sellPrice: resolved.sellPrice,
                    tierLevel: resolved.tierLevel,
                    isInherited: resolved.isInherited,
                    costLastUpdated: pwd.part.costLastUpdated,
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

    // MARK: - Helpers

    private func formatPrice(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    // MARK: - AI Context

    private func postPricingContext() {
        NotificationCenter.default.post(
            name: .pricingPageActive,
            object: nil,
            userInfo: ["context": buildAIContext()]
        )
    }

    private func buildAIContext() -> String {
        var context = "Page: Parts Pricing\n"
        context += "Pricing Mode: \(pricingMode == "markup" ? "Markup on Cost" : "Margin on Sell Price")\n"
        context += "Total Parts: \(pricingRows.count)\n"

        if let filter = filterCategory, let cat = categories.first(where: { $0.id == filter }) {
            context += "Filtered to Category: \(cat.name)\n"
        }

        guard !pricingRows.isEmpty else { return context }

        let avgMarkup = pricingRows.reduce(0.0) { $0 + $1.effectiveMarkup } / Double(pricingRows.count)
        let avgMargin = pricingRows.reduce(0.0) { $0 + $1.effectiveMargin } / Double(pricingRows.count)
        let avgCost = pricingRows.reduce(0.0) { $0 + $1.weightedAvgCost } / Double(pricingRows.count)
        let totalValue = pricingRows.reduce(0.0) { $0 + $1.sellPrice }
        let staleCount = pricingRows.filter(\.isStale).count

        context += "\n--- Pricing Summary ---\n"
        context += String(format: "Average Markup: %.1f%%\n", avgMarkup)
        context += String(format: "Average Margin: %.1f%%\n", avgMargin)
        context += String(format: "Average Cost: $%.2f\n", avgCost)
        context += String(format: "Total Sell Value: $%.2f\n", totalValue)
        context += "Stale Prices (not updated recently): \(staleCount)\n"

        // Tier distribution
        let tierGroups = Dictionary(grouping: pricingRows, by: \.tierLevel)
        context += "\n--- Price Sources ---\n"
        for (tier, parts) in tierGroups.sorted(by: { $0.key < $1.key }) {
            context += "\(tier): \(parts.count) parts\n"
        }

        // Top 5 highest markup parts
        let topMarkup = pricingRows.sorted(by: { $0.effectiveMarkup > $1.effectiveMarkup }).prefix(5)
        context += "\n--- Top 5 Highest Markup ---\n"
        for part in topMarkup {
            context += String(format: "  %@ — %.1f%% markup ($%.2f → $%.2f)\n",
                part.name, part.effectiveMarkup, part.weightedAvgCost, part.sellPrice)
        }

        // Top 5 lowest margin parts
        let lowMargin = pricingRows.sorted(by: { $0.effectiveMargin < $1.effectiveMargin }).prefix(5)
        context += "\n--- Top 5 Lowest Margin ---\n"
        for part in lowMargin {
            context += String(format: "  %@ — %.1f%% margin ($%.2f → $%.2f)\n",
                part.name, part.effectiveMargin, part.weightedAvgCost, part.sellPrice)
        }

        context += "\n--- Capabilities ---\n"
        context += "You can help the user with:\n"
        context += "- Analyzing pricing trends and suggesting markup adjustments\n"
        context += "- Identifying parts with unusually low or high margins\n"
        context += "- Explaining the difference between markup and margin\n"
        context += "- Recommending which parts need price updates (stale prices)\n"
        context += "- Suggesting competitive pricing strategies for categories\n"
        context += "- Explaining FIFO costing and how weighted averages work\n"

        return context
    }
}

// MARK: - Sort Options

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

// MARK: - Display Row

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
    let isStale: Bool           // true if > threshold days since last cost update
}

// MARK: - Active Sheet Enum

private enum PricingActiveSheet: Identifiable {
    case editPart(PricingDisplayRow)
    case setTierPricing
    case bulkEdit
    case pricingSettings
    case help

    var id: String {
        switch self {
        case .editPart(let row): return "edit-\(row.id)"
        case .setTierPricing: return "tier"
        case .bulkEdit: return "bulk"
        case .pricingSettings: return "settings"
        case .help: return "help"
        }
    }
}

// MARK: - View Mode Enum

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

// MARK: - Pricing Edit Sheet

struct PricingEditSheet: View {
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
    @State private var supplierCosts: [PartsService.PartSupplierCost] = []
    @State private var loadError: String?

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

                // Supplier costs
                Section("Supplier Costs") {
                    if supplierCosts.isEmpty {
                        Text("No supplier pricing data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(supplierCosts, id: \.supplierId) { sc in
                            HStack {
                                Text(sc.supplierName)
                                    .font(.subheadline)
                                if sc.isPreferred {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                                Spacer()
                                if let cost = sc.supplierCostPrice {
                                    Text(String(format: "$%.5f", cost))
                                        .font(.subheadline)
                                        .monospaced()
                                } else {
                                    Text("No price")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(minHeight: 36)
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
            supplierCosts = try service.getPartSupplierCosts(partId: row.id)
        } catch {
            loadError = error.localizedDescription
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
                _ = try service.setPricingTier(partId: row.id, fixedSellPrice: max(fixed, row.weightedAvgCost))
            } else if pricingMode == "markup" {
                let markup = max(Double(markupText) ?? 0, 0)
                _ = try service.setPricingTier(partId: row.id, markupPercent: markup)
            } else {
                let margin = max(Double(marginText) ?? 0, 0)
                _ = try service.setPricingTier(partId: row.id, marginPercent: margin)
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
