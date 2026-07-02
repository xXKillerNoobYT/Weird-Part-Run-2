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

    // Smart-card filter facet counts (GH#67)
    @State private var filterCounts: PartsService.CatalogFilterCounts?

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
        case cascadePriceEdit(colorId: Int64, colorName: String, typeId: Int64?, typeName: String?)
        case qrScanner
        case printLabels
        case help

        var id: String {
            switch self {
            case .addPart: return "addPart"
            case .partDetail(let p): return "detail-\(p.id)"
            case .quickEdit(let p): return "quickEdit-\(p.id)"
            case .editPricing(let r): return "pricing-\(r.id)"
            case .cascadePriceEdit(let cId, _, _, _): return "cascade-\(cId)"
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
    @State private var cascadePriceCache: [Int64: PartsService.ResolvedCascadeCost] = [:]
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

            // Smart-card stat filter bar — always visible
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
            Group {
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
            case .cascadePriceEdit(let colorId, let colorName, let typeId, let typeName):
                CascadePriceEditSheet(
                    colorId: colorId,
                    colorName: colorName,
                    typeId: typeId,
                    typeName: typeName
                ) {
                    await loadData()
                    await loadCascadePriceCache()
                }
                .environmentObject(appCore)
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
                        ("Overview", "Browse all parts in your inventory. Search by name or code, or use the smart filter cards to narrow by category, style, type, color, brand, or low stock. Each card shows how many parts match."),
                        ("Actions", "Tap the + button to add a new part. Use the QR scanner to find parts by code. The printer icon lets you print QR labels."),
                        ("Pricing", "Toggle the $ icon to show pricing overlays on each part. Tap a part for full details, long-press for quick edit.")
                    ]
                )
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        .task {
            // QR quick action "View Part" (#700): land on the scanned part by
            // filtering the catalog to its code — same behavior as this page's
            // own QR scan sheet.
            var scanRouteTriggeredLoad = false
            if let route = QRScanRouteStore.shared.consume(for: "parts-catalog"),
               route.entityType == .part {
                let query = route.searchHint ?? route.code
                if !query.isEmpty, query != searchText {
                    // Setting searchText fires .onChange(of: searchText) →
                    // resetAndLoad(), so skip the direct load below to avoid
                    // loading the catalog twice on first appear.
                    searchText = query
                    scanRouteTriggeredLoad = true
                }
            }
            await loadLookups()
            if !scanRouteTriggeredLoad {
                await loadData()
            }
            await loadCascadePriceCache()
        }
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

    // MARK: - Filter Bar (smart-card stat filters — GH#67)

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Parts — clears every filter; badge = parts matching the search only
                SmartFilterCard(
                    title: "All Parts",
                    count: filterCounts?.allParts ?? totalCount,
                    isSelected: !hasActiveFilters,
                    action: { clearAllFilters() }
                )

                // Category
                smartFilterMenuCard(
                    label: "Category",
                    selection: selectedCategoryId,
                    options: categories.compactMap { cat in cat.id.map { ($0, cat.name) } },
                    counts: filterCounts?.byCategory ?? [:]
                ) { newValue in
                    selectedCategoryId = newValue
                    // Clear dependent filters
                    selectedStyleId = nil
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Style (cascaded from category)
                smartFilterMenuCard(
                    label: "Style",
                    selection: selectedStyleId,
                    options: filteredStyles.compactMap { style in style.id.map { ($0, style.name) } },
                    counts: filterCounts?.byStyle ?? [:]
                ) { newValue in
                    selectedStyleId = newValue
                    selectedTypeId = nil
                    resetAndLoad()
                }

                // Type (cascaded from style)
                smartFilterMenuCard(
                    label: "Type",
                    selection: selectedTypeId,
                    options: filteredTypes.compactMap { type in type.id.map { ($0, type.name) } },
                    counts: filterCounts?.byType ?? [:]
                ) { newValue in
                    selectedTypeId = newValue
                    resetAndLoad()
                }

                // Color
                smartFilterMenuCard(
                    label: "Color",
                    selection: selectedColorId,
                    options: colors.compactMap { color in color.id.map { ($0, color.name) } },
                    counts: filterCounts?.byColor ?? [:]
                ) { newValue in
                    selectedColorId = newValue
                    resetAndLoad()
                }

                // Brand
                smartFilterMenuCard(
                    label: "Brand",
                    selection: selectedBrandId,
                    options: brands.compactMap { brand in brand.id.map { ($0, brand.name) } },
                    counts: filterCounts?.byBrand ?? [:]
                ) { newValue in
                    selectedBrandId = newValue
                    resetAndLoad()
                }

                // Low stock toggle — badge = low-stock parts under current filters
                SmartFilterCard(
                    title: "Low Stock",
                    count: filterCounts?.lowStock ?? 0,
                    isSelected: lowStockOnly,
                    action: {
                        lowStockOnly.toggle()
                        resetAndLoad()
                    }
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    /// A SmartFilterCard-styled menu for a filter dimension with per-option
    /// part counts. Badge shows the matching-part count for the current
    /// selection, or the number of available options when unselected.
    /// Choosing "All <label>s" from the menu clears the dimension.
    @ViewBuilder
    private func smartFilterMenuCard(
        label: String,
        selection: Int64?,
        options: [(Int64, String)],
        counts: [Int64: Int],
        onChange: @escaping (Int64?) -> Void
    ) -> some View {
        let selectedName = selection.flatMap { sel in options.first { $0.0 == sel }?.1 }
        let badgeCount = selection.map { counts[$0] ?? 0 }
            ?? options.filter { counts[$0.0] != nil }.count
        let isSelected = selection != nil

        Menu {
            Button("All \(label)s") { onChange(nil) }
            Divider()
            ForEach(options, id: \.0) { id, name in
                Button {
                    onChange(id)
                } label: {
                    let title = "\(name) (\(counts[id] ?? 0))"
                    if selection == id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(selectedName ?? label)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2).bold()
                        .accessibilityHidden(true)
                }
                Text("\(badgeCount)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 100, minHeight: 44)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .accessibilityLabel(isSelected
            ? "\(label) filter: \(selectedName ?? ""), \(badgeCount) matching parts"
            : "\(label) filter, \(badgeCount) options")
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

                // Pricing overlay (tier-based sell price)
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

                // Cascade price chip (color-level cost)
                if let colorId = part.colorId {
                    cascadePriceChip(part: part, colorId: colorId)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
    }

    // MARK: - Cascade Price Chip

    @ViewBuilder
    private func cascadePriceChip(part: CatalogPartRow, colorId: Int64) -> some View {
        if let cascade = cascadePriceCache[colorId] {
            Button {
                activeSheet = .cascadePriceEdit(
                    colorId: colorId,
                    colorName: part.colorName ?? "Color #\(colorId)",
                    typeId: part.typeId,
                    typeName: part.typeName
                )
            } label: {
                if let cost = cascade.effectiveCost {
                    HStack(spacing: 3) {
                        Text(String(format: "$%.2f", cost))
                            .font(.caption2)
                            .fontWeight(.medium)
                        if cascade.source == "type" {
                            Text("(default)")
                                .font(.caption2)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(cascade.source == "type" ? .orange : .blue)
                } else {
                    Text("No price")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
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

            // Facet counts for the smart-card filter bar (same filter state,
            // including the Low Stock toggle so badges match the visible list)
            let counts = try service.getCatalogFilterCounts(
                search: effectiveSearchText.isEmpty ? nil : effectiveSearchText,
                categoryId: selectedCategoryId,
                styleId: selectedStyleId,
                typeId: selectedTypeId,
                colorId: selectedColorId,
                brandId: selectedBrandId,
                lowStockOnly: lowStockOnly
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
                    typeId: pwd.part.typeId,
                    typeName: pwd.typeName,
                    colorId: pwd.part.colorId,
                    colorName: pwd.colorName,
                    brandId: pwd.part.brandId,
                    brandName: pwd.brandName,
                    companyCostPrice: pwd.part.companyCostPrice,
                    companyMarkupPercent: pwd.part.companyMarkupPercent,
                    totalStock: stock,
                    partType: pwd.part.partType,
                    isActive: pwd.part.isActive ?? 1,
                    autoAddToWishlistWhenLow: pwd.part.autoAddToWishlistWhenLow != 0,
                    isLowStock: minStock.map { stock < $0 } ?? false
                )
            }

            await MainActor.run {
                totalCount = result.totalCount
                parts = prows
                filterCounts = counts
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
        let mode: String
        do {
            mode = try service.getCompanyCostSetting(key: "pricing_mode") ?? "markup"
        } catch {
            mode = "markup" // Fallback default; settings table may not exist yet
        }
        await MainActor.run {
            partPricingCache = cache
            pricingMode = mode
        }
    }

    // MARK: - Cascade Price Cache

    private func loadCascadePriceCache() async {
        guard let service = appCore.partsService else {
            await MainActor.run { actionError = "Parts service unavailable" }
            return
        }
        var cache: [Int64: PartsService.ResolvedCascadeCost] = [:]
        for part in parts {
            guard let colorId = part.colorId else { continue }
            // Skip if already cached
            if cascadePriceCache[colorId] != nil && cache[colorId] != nil { continue }
            do {
                let resolved = try service.getEffectivePrice(colorId: colorId, typeId: part.typeId)
                cache[colorId] = resolved
            } catch {
                // Non-critical: chip won't show for this color
            }
        }
        await MainActor.run { cascadePriceCache = cache }
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
    let typeId: Int64?
    let typeName: String?
    let colorId: Int64?
    let colorName: String?
    let brandId: Int64?
    let brandName: String?
    let companyCostPrice: Double
    let companyMarkupPercent: Double
    let totalStock: Int
    let partType: String
    let isActive: Int
    let autoAddToWishlistWhenLow: Bool
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
    @State private var originalName: String = ""
    @State private var originalCode: String = ""
    @State private var originalCostPrice: String = ""
    @State private var originalMarkup: String = ""

    private var isDirty: Bool {
        name != originalName || code != originalCode ||
        costPrice != originalCostPrice || markupPercent != originalMarkup
    }

    private var pricingValidationMessage: String? {
        do {
            _ = try ManualPricingInputValidator.parseMoney(costPrice, fieldName: "Cost")
            _ = try ManualPricingInputValidator.parsePercent(markupPercent, fieldName: "Markup")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var sellPrice: Double? {
        guard let cost = try? ManualPricingInputValidator.parseMoney(costPrice, fieldName: "Cost"),
              let markup = try? ManualPricingInputValidator.parsePercent(markupPercent, fieldName: "Markup") else {
            return nil
        }
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
                    LabeledContent("Sell Price", value: sellPrice.map { String(format: "$%.2f", $0) } ?? "—")
                        .foregroundStyle(.secondary)
                    if let pricingValidationMessage {
                        Label(pricingValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .accessibilityIdentifier("manual-pricing-validation-error")
                    }
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
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pricingValidationMessage != nil || isSaving)
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .onAppear {
                name = part.name
                code = part.code ?? ""
                costPrice = String(format: "%.2f", part.companyCostPrice)
                markupPercent = String(format: "%.1f", part.companyMarkupPercent)
                originalName = part.name
                originalCode = part.code ?? ""
                originalCostPrice = costPrice
                originalMarkup = markupPercent
            }
            .alert("Error", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        let cost: Double
        let markup: Double
        do {
            cost = try ManualPricingInputValidator.parseMoney(costPrice, fieldName: "Cost")
            markup = try ManualPricingInputValidator.parsePercent(markupPercent, fieldName: "Markup")
        } catch {
            saveError = error.localizedDescription
            return
        }

        isSaving = true

        do {
            try service.updatePart(
                id: part.id,
                name: trimmedName,
                code: code.isEmpty ? nil : code,
                companyCostPrice: cost,
                companyMarkupPercent: markup
            )
            await MainActor.run { dismiss() }
            await onSave()
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
    @State private var autoAddToWishlistWhenLow = false
    @State private var saveError: String?
    @State private var isSaving = false

    private let partTypes = ["standard", "special_order", "custom"]

    private var pricingValidationMessage: String? {
        do {
            _ = try ManualPricingInputValidator.parseMoney(costPrice, fieldName: "Cost Price")
            _ = try ManualPricingInputValidator.parsePercent(markupPercent, fieldName: "Markup")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

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
                    if let pricingValidationMessage {
                        Label(pricingValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .accessibilityIdentifier("manual-pricing-validation-error")
                    }
                }

                if appCore.hasPermission("edit_parts_catalog") {
                    Section("Automation") {
                        Toggle("Auto-add to wishlist when low", isOn: $autoAddToWishlistWhenLow)
                    }
                }
            }
            .navigationTitle(part == nil ? "New Part" : "Edit Part")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                await save()
                                isSaving = false
                                if saveError == nil {
                                    dismiss()
                                    await onSave()
                                }
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategoryId == 0 || pricingValidationMessage != nil)
                    }
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
                    autoAddToWishlistWhenLow = p.autoAddToWishlistWhenLow
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, selectedCategoryId > 0 else { return }
        let cost: Double
        let markup: Double
        do {
            cost = try ManualPricingInputValidator.parseMoney(costPrice, fieldName: "Cost Price")
            markup = try ManualPricingInputValidator.parsePercent(markupPercent, fieldName: "Markup")
        } catch {
            saveError = error.localizedDescription
            return
        }
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        do {
            let savedPartId: Int64
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
                savedPartId = p.id
            } else {
                savedPartId = try service.createPart(
                    categoryId: selectedCategoryId,
                    name: trimmedName,
                    partType: partType,
                    code: code.isEmpty ? nil : code,
                    brandId: selectedBrandId,
                    companyCostPrice: cost,
                    companyMarkupPercent: markup
                )
            }
            if appCore.hasPermission("edit_parts_catalog"), let userId = appCore.currentUser?.id {
                try service.setAutoAddToWishlistWhenLow(
                    partId: savedPartId,
                    enabled: autoAddToWishlistWhenLow,
                    byUserId: userId
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
                    LabeledContent(
                        "Auto Wishlist",
                        value: partRow.autoAddToWishlistWhenLow ? "Enabled" : "Disabled"
                    )
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
                do {
                    names = try whService.getWarehouseLocationNames(ids: ids)
                } catch {
                    // Non-critical: stock entries still display, just without location names
                    names = [:]
                }
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
