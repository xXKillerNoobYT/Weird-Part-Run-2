import SwiftUI
import WiredPartCore

/// Full parts catalog with cascading hierarchy filters, pagination,
/// low-stock indicator, and a quick-edit sheet.
///
/// Matches the Windows/React catalog feature set adapted for mobile:
///   - Cascading filters: Category → Style → Type → Color → Brand
///   - Sortable list with tap-to-sort headers
///   - Pagination (25 per page)
///   - Low-stock filter toggle
///   - Quick-edit modal (name, code, cost, markup)
///   - Swipe-to-delete
struct PartsCatalogPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data
    @State private var parts: [CatalogPartRow] = []
    @State private var totalCount = 0
    @State private var isLoading = true

    // Lookup tables for hierarchy filters
    @State private var categories: [PartCategory] = []
    @State private var styles: [PartStyle] = []
    @State private var types: [PartType] = []
    @State private var colors: [PartColor] = []
    @State private var brands: [Brand] = []

    // MARK: - Filters
    @State private var searchText = ""
    @State private var selectedCategoryId: Int64?
    @State private var selectedStyleId: Int64?
    @State private var selectedTypeId: Int64?
    @State private var selectedColorId: Int64?
    @State private var selectedBrandId: Int64?
    @State private var lowStockOnly = false

    // MARK: - Sorting
    @State private var sortField: SortField = .name
    @State private var sortAscending = true

    // MARK: - Pagination
    @State private var currentPage = 1
    private let pageSize = 25

    // MARK: - Sheets (single enum to avoid multiple .sheet conflicts)
    enum ActiveSheet: Identifiable {
        case addPart
        case partDetail(CatalogPartRow)
        case quickEdit(CatalogPartRow)
        case editPricing(PricingDisplayRow)
        case qrScanner
        case printLabels
        case help

        var id: String {
            switch self {
            case .addPart: return "addPart"
            case .partDetail(let p): return "detail-\(p.id)"
            case .quickEdit(let p): return "quickEdit-\(p.id)"
            case .editPricing(let r): return "pricing-\(r.id)"
            case .qrScanner: return "qrScanner"
            case .printLabels: return "printLabels"
            case .help: return "help"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var partToDelete: CatalogPartRow?

    // Pricing overlay
    @State private var showPricing = false
    @State private var partPricingCache: [Int64: PartsService.ResolvedPricing] = [:]
    @State private var pricingMode: String = "markup"

    // MARK: - Cascading filter options
    private var filteredStyles: [PartStyle] {
        guard let catId = selectedCategoryId else { return styles }
        return styles.filter { $0.categoryId == catId }
    }
    private var filteredTypes: [PartType] {
        guard let styleId = selectedStyleId else { return types }
        return types.filter { $0.styleId == styleId }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "parts-catalog")
            SkippedModuleHint(moduleId: "parts")

            // Fixed search bar — always visible, never scrolls away
            searchBar

            // Smart search banner
            nlFilterBanner

            // Filter chips bar — always visible
            filterBar

            // Sort header
            sortHeader

            if isLoading {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if parts.isEmpty {
                emptyState
            } else {
                partsList
                paginationBar
            }
        }
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            let parsed = parseNaturalLanguageSearch(trimmed)

            if parsed.hasStructuredFilters {
                selectedCategoryId = parsed.categoryId
                selectedStyleId = parsed.styleId
                selectedTypeId = parsed.typeId
                selectedColorId = parsed.colorId
                selectedBrandId = parsed.brandId
                lowStockOnly = parsed.lowStock
            }

            if !trimmed.isEmpty {
                appCore.onboardingManager?.markCompleted("catalog-search")
            }

            resetAndLoad()
        }
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPricing.toggle()
                } label: {
                    Image(systemName: showPricing ? "dollarsign.circle.fill" : "dollarsign.circle")
                }
                .accessibilityLabel(showPricing ? "Hide pricing" : "Show pricing")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    activeSheet = .printLabels
                } label: {
                    Image(systemName: "printer")
                }
                .accessibilityLabel("Print labels")
                Button {
                    activeSheet = .qrScanner
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan QR code")
                Button {
                    activeSheet = .addPart
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add new part")
            }
        }
        .onChange(of: showPricing) {
            Task { await loadPricingCache() }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addPart:
                PartFormSheet(part: nil, categories: categories, brands: brands) { await loadData() }
            case .partDetail(let partRow):
                PartDetailSheet(partRow: partRow, categories: categories, brands: brands) { await loadData() }
            case .quickEdit(let partRow):
                QuickEditSheet(part: partRow) { await loadData() }
            case .editPricing(let row):
                PricingEditSheet(row: row, pricingMode: pricingMode) {
                    await loadData()
                    await loadPricingCache()
                }
            case .qrScanner:
                QRScanSheet(expectedType: nil) { result in
                    if result.isFound, result.entityType == .part {
                        // Set search text to filter catalog to the scanned part
                        searchText = result.fields["code"] ?? result.fields["name"] ?? result.code
                    } else if !result.isFound {
                        // External barcode — search by raw code
                        searchText = result.code
                    }
                }
                .environmentObject(appCore)
            case .printLabels:
                QRLabelPrintSheet(items: parts.map { part in
                    QRLabelContent(
                        entityType: .part,
                        entityId: part.id,
                        code: part.code ?? "",
                        title: part.name,
                        subtitle: part.categoryName,
                        detail: part.brandName
                    )
                })
            case .help:
                PageHelpSheet(
                    title: "Parts Catalog Help",
                    sections: [
                        ("Overview", "Browse all parts in your inventory. Search by name or code, filter by category, brand, or stock status using the chips."),
                        ("Actions", "Tap the + button to add a new part. Use the QR scanner to find parts by code. The printer icon lets you print QR labels."),
                        ("Pricing", "Toggle the $ icon to show pricing overlays on each part. Tap a part for full details, long-press for quick edit.")
                    ]
                )
            }
        }
        .background(DS.Background.page)
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
        .onReceive(NotificationCenter.default.publisher(for: .aiSetCatalogFilters)) { notification in
            if let userInfo = notification.userInfo {
                if let categoryName = userInfo["category"] as? String {
                    selectedCategoryId = categories.first(where: {
                        $0.name.lowercased() == categoryName.lowercased()
                    })?.id
                }
                if let styleName = userInfo["style"] as? String {
                    selectedStyleId = styles.first(where: {
                        $0.name.lowercased() == styleName.lowercased()
                    })?.id
                }
                if let typeName = userInfo["type"] as? String {
                    selectedTypeId = types.first(where: {
                        $0.name.lowercased() == typeName.lowercased()
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
        .task { await loadLookups(); await loadData() }
        .alert("Error", isPresented: Binding<Bool>(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search parts by name, code, or brand...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Category
                filterMenu(
                    label: "Category",
                    icon: "folder.fill",
                    selection: selectedCategoryId,
                    options: categories.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedCategoryId = newValue
                    // Clear dependent filters
                    selectedStyleId = nil
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Style (cascaded from category)
                filterMenu(
                    label: "Style",
                    icon: "paintpalette.fill",
                    selection: selectedStyleId,
                    options: filteredStyles.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedStyleId = newValue
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Type (cascaded from style)
                filterMenu(
                    label: "Type",
                    icon: "square.grid.2x2.fill",
                    selection: selectedTypeId,
                    options: filteredTypes.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedTypeId = newValue
                    resetAndLoad()
                }

                // Color
                filterMenu(
                    label: "Color",
                    icon: "drop.fill",
                    selection: selectedColorId,
                    options: colors.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedColorId = newValue
                    resetAndLoad()
                }

                // Brand
                filterMenu(
                    label: "Brand",
                    icon: "tag.fill",
                    selection: selectedBrandId,
                    options: brands.compactMap { ($0.id, $0.name) }
                ) { newValue in
                    selectedBrandId = newValue
                    resetAndLoad()
                }

                // Low stock toggle
                Button {
                    lowStockOnly.toggle()
                    resetAndLoad()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Low Stock")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(lowStockOnly ? Color.orange.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(lowStockOnly ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.3), lineWidth: 1))
                }

                // Clear all
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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var hasActiveFilters: Bool {
        selectedCategoryId != nil || selectedStyleId != nil ||
        selectedTypeId != nil || selectedColorId != nil ||
        selectedBrandId != nil || lowStockOnly
    }

    private func clearAllFilters() {
        selectedCategoryId = nil
        selectedStyleId = nil
        selectedTypeId = nil
        selectedColorId = nil
        selectedBrandId = nil
        lowStockOnly = false
        resetAndLoad()
    }

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
                    .accessibilityHidden(true)
                Text(selection.flatMap { sel in options.first { $0.0 == sel }?.1 } ?? label)
                    .font(.caption)
                    .fontWeight(selection != nil ? .semibold : .regular)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2).bold()
                    .accessibilityHidden(true)
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

    // MARK: - Sort Header

    private var sortHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                sortButton("Name", field: .name)
                sortButton("Code", field: .code)
                sortButton("Category", field: .category)
                sortButton("Brand", field: .brand)
                sortButton("Stock", field: .stock)
                sortButton("Cost", field: .cost)
                sortButton("Sell", field: .sell)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
    }

    @ViewBuilder
    private func sortButton(_ label: String, field: SortField) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
            resetAndLoad()
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(sortField == field ? .bold : .regular)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(sortField == field ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Parts List

    @ViewBuilder
    private var partsList: some View {
        List {
            Section {
                Text("\(totalCount) part\(totalCount == 1 ? "" : "s") · Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(parts, id: \.id) { part in
                Button {
                    activeSheet = .partDetail(part)
                } label: {
                    partRow(part)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        partToDelete = part
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        activeSheet = .quickEdit(part)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "Delete Part?",
            isPresented: Binding(
                get: { partToDelete != nil },
                set: { if !$0 { partToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let part = partToDelete {
                    Task { await deletePart(part) }
                }
            }
            Button("Cancel", role: .cancel) { partToDelete = nil }
        } message: {
            if let part = partToDelete {
                Text("Are you sure you want to delete \"\(part.name)\"? This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func partRow(_ part: CatalogPartRow) -> some View {
        HStack(spacing: 12) {
            // Icon with low-stock indicator
            ZStack(alignment: .topTrailing) {
                VStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if part.isLowStock {
                    Circle()
                        .fill(.orange)
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                        .accessibilityLabel("Low stock")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(part.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let code = part.code, !code.isEmpty {
                        Text(code)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    if let catName = part.categoryName {
                        Text(catName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if let brandName = part.brandName {
                        Text(brandName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if appCore.hasPermission("show_dollar_values") {
                    Text(String(format: "$%.2f", part.companyCostPrice))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text("\(part.totalStock) in stock")
                    .font(.caption)
                    .foregroundStyle(part.totalStock > 0 ? .green : .red)

                // Pricing overlay
                if showPricing, let pricing = partPricingCache[part.id] {
                    Button {
                        let displayRow = PricingDisplayRow(
                            id: part.id,
                            name: part.name,
                            code: part.code,
                            categoryName: part.categoryName ?? "",
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
                        HStack(spacing: 4) {
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
                    .buttonStyle(.plain)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
    }

    // MARK: - Pagination Bar

    private var totalPages: Int {
        max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
    }

    @ViewBuilder
    private var paginationBar: some View {
        HStack {
            Button {
                if currentPage > 1 {
                    currentPage -= 1
                    Task { await loadData() }
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .disabled(currentPage <= 1)

            Spacer()

            Text("Page \(currentPage) of \(totalPages)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if currentPage < totalPages {
                    currentPage += 1
                    Task { await loadData() }
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .font(.subheadline)
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage >= totalPages)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .decorativeIconFont(48)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Parts Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text(hasActiveFilters || !searchText.isEmpty
                 ? "Try adjusting your filters or search."
                 : "Add parts to your catalog to start tracking inventory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !hasActiveFilters && searchText.isEmpty {
                Button {
                    activeSheet = .addPart
                } label: {
                    Label("Add Part", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Catalog Context for AI

    /// Current catalog page state for AI context.
    struct CatalogContext {
        let activeFilters: [String: String]
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

    // MARK: - NL Search Parser

    struct NLSearchResult {
        var categoryId: Int64?
        var styleId: Int64?
        var typeId: Int64?
        var colorId: Int64?
        var brandId: Int64?
        var lowStock: Bool = false
        var textSearch: String = ""

        var hasStructuredFilters: Bool {
            categoryId != nil || styleId != nil || typeId != nil ||
            colorId != nil || brandId != nil || lowStock
        }
    }

    /// Parse natural language search text into structured filters.
    ///
    /// Examples:
    ///   "low stock white elbows from Lutron"
    ///     → lowStock: true, color: "White", type matches "elbows", brand: "Lutron"
    ///   "PVC fittings"
    ///     → category matches "Fittings", style matches "PVC"
    private func parseNaturalLanguageSearch(_ text: String) -> NLSearchResult {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else {
            return NLSearchResult()
        }

        var result = NLSearchResult()

        let fillerWords: Set<String> = ["from", "by", "in", "the", "a", "an", "with", "for", "all", "show", "find", "me", "get"]
        let tokens = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty && !fillerWords.contains($0) }

        if lower.contains("low stock") || lower.contains("lowstock") || lower.contains("low-stock") {
            result.lowStock = true
        }

        var matchedTokenIndices: Set<Int> = []

        // Match brands (can be multi-word)
        for brand in brands {
            if lower.contains(brand.name.lowercased()) {
                result.brandId = brand.id
                let brandTokens = brand.name.lowercased().components(separatedBy: .whitespaces)
                for (i, token) in tokens.enumerated() {
                    if brandTokens.contains(token) { matchedTokenIndices.insert(i) }
                }
                break
            }
        }

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

        var remainingTerms: [String] = []
        for (i, token) in tokens.enumerated() {
            if !matchedTokenIndices.contains(i) && token != "low" && token != "stock" {
                remainingTerms.append(token)
            }
        }
        result.textSearch = remainingTerms.joined(separator: " ")

        return result
    }

    @ViewBuilder
    private var nlFilterBanner: some View {
        let parsed = parseNaturalLanguageSearch(searchText)
        if parsed.hasStructuredFilters {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
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

    // MARK: - Helpers

    private func resetAndLoad() {
        currentPage = 1
        Task { await loadData() }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadLookups() async {
        guard let service = appCore.partsService else {
            await MainActor.run { loadError = "Service not available"; isLoading = false }
            return
        }
        do {
            let cats = try service.listCategories()
            let stys = try service.listStyles()
            let typs = try service.listTypes()
            let cols = try service.listColors()
            let brnds = try service.listBrands().map(\.brand)

            await MainActor.run {
                categories = cats
                styles = stys
                types = typs
                colors = cols
                brands = brnds
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load parts catalog")
                isLoading = false
            }
        }
    }

    @Sendable
    private func loadData() async {
        await MainActor.run { isLoading = parts.isEmpty }
        guard let service = appCore.partsService else {
            await MainActor.run { loadError = "Service not available"; isLoading = false }
            return
        }

        do {
            let offset = (currentPage - 1) * pageSize

            let parsed = parseNaturalLanguageSearch(searchText)
            let effectiveSearchText = parsed.hasStructuredFilters ? parsed.textSearch : searchText.trimmingCharacters(in: .whitespaces)

            let catalogSort: PartsService.CatalogSortField = switch sortField {
            case .name: .name
            case .code: .code
            case .category: .category
            case .brand: .brand
            case .stock: .stock
            case .cost: .cost
            case .sell: .sell
            }

            let result = try service.listCatalogParts(
                search: effectiveSearchText.isEmpty ? nil : effectiveSearchText,
                categoryId: selectedCategoryId,
                styleId: selectedStyleId,
                typeId: selectedTypeId,
                colorId: selectedColorId,
                brandId: selectedBrandId,
                lowStockOnly: lowStockOnly,
                sortField: catalogSort,
                sortAscending: sortAscending,
                limit: pageSize,
                offset: offset
            )

            let prows = result.parts.map { pwd -> CatalogPartRow in
                let stock = pwd.totalStock
                let minStock = pwd.part.minStockLevel
                return CatalogPartRow(
                    id: pwd.part.id ?? 0,
                    name: pwd.part.name,
                    code: pwd.part.code,
                    categoryId: pwd.part.categoryId,
                    categoryName: pwd.categoryName,
                    styleId: pwd.part.styleId,
                    styleName: pwd.styleName,
                    colorId: pwd.part.colorId,
                    colorName: pwd.colorName,
                    brandId: pwd.part.brandId,
                    brandName: pwd.brandName,
                    companyCostPrice: pwd.part.companyCostPrice,
                    companyMarkupPercent: pwd.part.companyMarkupPercent,
                    totalStock: stock,
                    partType: pwd.part.partType,
                    isActive: pwd.part.isActive ?? 1,
                    isLowStock: minStock.map { stock < $0 } ?? false
                )
            }

            await MainActor.run {
                totalCount = result.totalCount
                parts = prows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load parts catalog")
                isLoading = false
            }
        }
    }

    // MARK: - Pricing Cache

    private func loadPricingCache() async {
        guard showPricing else {
            await MainActor.run { partPricingCache = [:] }
            return
        }
        guard let service = appCore.partsService else {
            await MainActor.run { loadError = "Parts service not available"; isLoading = false }
            return
        }
        var cache: [Int64: PartsService.ResolvedPricing] = [:]
        for part in parts {
            do {
                let resolved = try service.resolvePartPricing(partId: part.id)
                cache[part.id] = resolved
            } catch {
                // Non-critical: part still displays, just without pricing overlay.
                // Pricing resolution can fail for parts without configured tiers.
            }
        }
        // Also load pricing mode
        let mode = (try? service.getCompanyCostSetting(key: "pricing_mode")) ?? "markup"
        await MainActor.run {
            partPricingCache = cache
            pricingMode = mode
        }
    }

    // MARK: - Delete

    private func deletePart(_ part: CatalogPartRow) async {
        guard let service = appCore.partsService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.deletePart(id: part.id)
            await loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }
}

// MARK: - Sort Field

private enum SortField: String {
    case name, code, category, brand, stock, cost, sell
}

// MARK: - Catalog Part Row Model

struct CatalogPartRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let categoryId: Int64
    let categoryName: String?
    let styleId: Int64?
    let styleName: String?
    let colorId: Int64?
    let colorName: String?
    let brandId: Int64?
    let brandName: String?
    let companyCostPrice: Double
    let companyMarkupPercent: Double
    let totalStock: Int
    let partType: String
    let isActive: Int
    let isLowStock: Bool
}

// MARK: - Quick Edit Sheet

private struct QuickEditSheet: View {
    let part: CatalogPartRow
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var costPrice: String = ""
    @State private var markupPercent: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var sellPrice: Double {
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        return cost * (1 + markup / 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part Info") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Code", text: $code)
                        .frame(minHeight: 44)
                }

                Section("Hierarchy") {
                    if let cat = part.categoryName {
                        LabeledContent("Category", value: cat)
                    }
                    if let style = part.styleName {
                        LabeledContent("Style", value: style)
                    }
                    if let color = part.colorName {
                        LabeledContent("Color", value: color)
                    }
                    if let brand = part.brandName {
                        LabeledContent("Brand", value: brand)
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("$")
                        TextField("Cost", text: $costPrice)
                            .keyboardType(.decimalPad)
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Markup %", text: $markupPercent)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                    LabeledContent("Sell Price", value: String(format: "$%.2f", sellPrice))
                        .foregroundStyle(.secondary)
                }

                Section("Stock") {
                    LabeledContent("In Stock", value: "\(part.totalStock)")
                    LabeledContent("Status", value: part.isLowStock ? "Low Stock ⚠️" : "OK")
                }
            }
            .navigationTitle("Quick Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                name = part.name
                code = part.code ?? ""
                costPrice = String(format: "%.2f", part.companyCostPrice)
                markupPercent = String(format: "%.1f", part.companyMarkupPercent)
            }
            .alert("Error", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        isSaving = true
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0

        do {
            try service.updatePart(
                id: part.id,
                name: trimmedName,
                code: code.isEmpty ? nil : code,
                companyCostPrice: cost,
                companyMarkupPercent: markup
            )
            await onSave()
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                saveError = userFriendlyError(error, context: "save data")
                isSaving = false
            }
        }
    }
}

// MARK: - Part Form Sheet (Add/Full Edit)

private struct PartFormSheet: View {
    let part: CatalogPartRow?
    let categories: [PartCategory]
    let brands: [Brand]
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var code = ""
    @State private var selectedCategoryId: Int64 = 0
    @State private var selectedBrandId: Int64?
    @State private var partType = "standard"
    @State private var costPrice = ""
    @State private var markupPercent = ""
    @State private var saveError: String?

    private let partTypes = ["standard", "special_order", "custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Part Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Part Code (optional)", text: $code)
                        .frame(minHeight: 44)
                    Picker("Type", selection: $partType) {
                        ForEach(partTypes, id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                        }
                    }
                }

                Section("Classification") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Select…").tag(Int64(0))
                        ForEach(categories, id: \.id) { cat in
                            Text(cat.name).tag(cat.id ?? Int64(0))
                        }
                    }
                    Picker("Brand", selection: Binding(
                        get: { selectedBrandId ?? -1 },
                        set: { selectedBrandId = $0 == -1 ? nil : $0 }
                    )) {
                        Text("None").tag(Int64(-1))
                        ForEach(brands, id: \.id) { brand in
                            Text(brand.name).tag(brand.id ?? Int64(-1))
                        }
                    }
                }

                Section("Pricing") {
                    HStack {
                        Text("$")
                        TextField("Cost Price", text: $costPrice)
                            .keyboardType(.decimalPad)
                    }
                    .frame(minHeight: 44)
                    HStack {
                        TextField("Markup %", text: $markupPercent)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(part == nil ? "New Part" : "Edit Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategoryId == 0)
                }
            }
            .onAppear {
                if let p = part {
                    name = p.name
                    code = p.code ?? ""
                    selectedCategoryId = p.categoryId
                    selectedBrandId = p.brandId
                    partType = p.partType
                    costPrice = String(format: "%.2f", p.companyCostPrice)
                    markupPercent = String(format: "%.1f", p.companyMarkupPercent)
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, selectedCategoryId > 0 else { return }
        let cost = Double(costPrice) ?? 0
        let markup = Double(markupPercent) ?? 0
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        do {
            if let p = part {
                try service.updatePart(
                    id: p.id,
                    name: trimmedName,
                    code: code.isEmpty ? nil : code,
                    categoryId: selectedCategoryId,
                    brandId: selectedBrandId,
                    partType: partType,
                    companyCostPrice: cost,
                    companyMarkupPercent: markup
                )
            } else {
                _ = try service.createPart(
                    categoryId: selectedCategoryId,
                    name: trimmedName,
                    partType: partType,
                    code: code.isEmpty ? nil : code,
                    brandId: selectedBrandId,
                    companyCostPrice: cost,
                    companyMarkupPercent: markup
                )
            }
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }
}

// MARK: - Part Detail Sheet

private struct PartDetailSheet: View {
    let partRow: CatalogPartRow
    let categories: [PartCategory]
    let brands: [Brand]
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var stockEntries: [StockEntry] = []
    @State private var warehouseNames: [Int64: String] = [:]
    @State private var showEditForm = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Part Information") {
                    LabeledContent("Name", value: partRow.name)
                    if let code = partRow.code {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Type", value: partRow.partType.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let cat = partRow.categoryName {
                        LabeledContent("Category", value: cat)
                    }
                    if let style = partRow.styleName {
                        LabeledContent("Style", value: style)
                    }
                    if let color = partRow.colorName {
                        LabeledContent("Color", value: color)
                    }
                    if let brand = partRow.brandName {
                        LabeledContent("Brand", value: brand)
                    }
                    LabeledContent("Status", value: partRow.isActive == 1 ? "Active" : "Inactive")
                }

                if appCore.hasPermission("show_dollar_values") {
                    Section("Pricing") {
                        LabeledContent("Cost Price", value: String(format: "$%.2f", partRow.companyCostPrice))
                        LabeledContent("Markup", value: String(format: "%.1f%%", partRow.companyMarkupPercent))
                        let sellPrice = partRow.companyCostPrice * (1 + partRow.companyMarkupPercent / 100)
                        LabeledContent("Sell Price", value: String(format: "$%.2f", sellPrice))
                    }
                }

                Section("Stock (\(partRow.totalStock) total)") {
                    if stockEntries.isEmpty {
                        Text("No stock entries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stockEntries, id: \.id) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(warehouseNames[entry.warehouseId] ?? "Location #\(entry.warehouseId)")
                                        .font(.subheadline)
                                    if let bin = entry.binLocation {
                                        Text("Bin: \(bin)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(entry.quantity)")
                                    .font(.headline)
                                    .foregroundStyle(entry.quantity > 0 ? .green : .red)
                            }
                        }
                    }
                }

                Section("Change History") {
                    DisclosureGroup("View History") {
                        PartHistoryView(partId: partRow.id)
                    }
                }
            }
            .navigationTitle("Part Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showEditForm = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit part")
                }
            }
            .sheet(isPresented: $showEditForm) {
                PartFormSheet(part: partRow, categories: categories, brands: brands) {
                    await onUpdate()
                }
            }
            .task { await loadStock() }
            .task { appCore.onboardingManager?.markCompleted("catalog-detail") }
        }
    }

    @Sendable
    private func loadStock() async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            let entries = try service.listStockEntries(partId: partRow.id)

            // Batch-load human-readable warehouse location names
            var names: [Int64: String] = [:]
            if !entries.isEmpty, let whService = appCore.warehouseService {
                let ids = Array(Set(entries.map(\.warehouseId)))
                names = (try? whService.getWarehouseLocationNames(ids: ids)) ?? [:]
            }

            await MainActor.run {
                stockEntries = entries
                warehouseNames = names
            }
        } catch {
            loadError = userFriendlyError(error, context: "load parts catalog")
        }
    }
}
