import SwiftUI
import WiredPartCore

/// Enum representing which node in the hierarchy tree is selected.
enum TreeSelection: Equatable {
    case category(Int64)
    case style(Int64)
    case type(Int64)
    case brand(brandId: Int64, typeId: Int64)
    case color(colorId: Int64, typeId: Int64, brandId: Int64?)
    case sku(skuId: Int64, typeId: Int64, brandId: Int64, colorId: Int64)
}

/// Left-panel tree browser: 5-level nested hierarchy showing
/// Category > Style > Type > Brand > Color.
///
/// Uses manual expand/collapse state so that tapping a row
/// both **selects** it AND **expands/collapses** its children.
struct CategoriesTreeView: View {
    @EnvironmentObject private var appCore: AppCore
    let hierarchy: PartsService.HierarchyTree
    @Binding var selection: TreeSelection?

    // Expand/collapse state lifted to parent so data refreshes don't reset the tree.
    @Binding var expandedCategories: Set<Int64>
    @Binding var expandedStyles: Set<Int64>
    @Binding var expandedTypes: Set<Int64>
    @Binding var expandedBrands: Set<Int64>
    @State private var searchText = ""

    /// Cache of effective cost per colorId, loaded alongside hierarchy.
    @State private var colorPriceCache: [Int64: Double?] = [:]
    @State private var colorPriceError: String?
    @State private var skuCache: [String: [PartsService.ColorBrandSKU]] = [:]
    @State private var skuLoadErrors: [String: String] = [:]

    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addCategory
        case addStyle(Int64)
        case addType(Int64)
        case addColor
        case help
        case editColorPrice(colorId: Int64, typeId: Int64)
        case pricingOverride

        var id: String {
            switch self {
            case .addCategory: return "addCategory"
            case .addStyle(let id): return "addStyle-\(id)"
            case .addType(let id): return "addType-\(id)"
            case .addColor: return "addColor"
            case .help: return "help"
            case .editColorPrice(let cId, let tId): return "editColorPrice-\(cId)-\(tId)"
            case .pricingOverride: return "pricingOverride"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    var onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Parts Hierarchy")
                    .font(.headline)

                Button {
                    activeSheet = .help
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Help")

                Spacer()
                Menu {
                    Button { activeSheet = .addCategory } label: {
                        Label("New Category", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("addCategoryMenuItem")
                    Button { activeSheet = .addColor } label: {
                        Label("New Color", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("addColorMenuItem")
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityIdentifier("categoriesAddMenu")
                .accessibilityLabel("Add category or color")
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)

            Divider()

            // Search field
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .accessibilityHidden(true)
                TextField("Search hierarchy...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .accessibilityIdentifier("categoriesSearchField")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)

            if let colorPriceError {
                Label(colorPriceError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.bottom, DS.Space.sm)
            }

            if filteredCategories.isEmpty {
                if searchText.isEmpty {
                    VStack(spacing: DS.Space.lg) {
                        Spacer()

                        Image(systemName: "folder.badge.questionmark")
                            .decorativeIconFont(48)
                            .foregroundStyle(.secondary)

                        Text("No Categories Yet")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("The parts hierarchy organizes your inventory into 5 levels:\nCategory > Style > Type > Brand > Color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Space.xl)

                        VStack(spacing: DS.Space.sm) {
                            Button {
                                activeSheet = .addCategory
                            } label: {
                                Label("Create First Category", systemImage: "plus.circle.fill")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: 240)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("createFirstCategoryButton")

                            Button {
                                activeSheet = .help
                            } label: {
                                Label("Learn How It Works", systemImage: "questionmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredCategories) { catNode in
                            categorySection(catNode)
                        }
                    }
                    .padding(.vertical, DS.Space.sm)
                }
                .accessibilityIdentifier("categoriesTreeList")
            }
        }
        .onChange(of: searchText) {
            if !searchText.isEmpty {
                // Auto-expand all nodes in filtered results
                for catNode in filteredCategories {
                    if let catId = catNode.category.id {
                        expandedCategories.insert(catId)
                    }
                    for styleNode in catNode.styles {
                        if let styleId = styleNode.style.id {
                            expandedStyles.insert(styleId)
                        }
                        for typeNode in styleNode.types {
                            if let typeId = typeNode.type.id {
                                expandedTypes.insert(typeId)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            // Safety net: always refresh when any sheet closes,
            // even if the save callback didn't fire (e.g. user pulled down to dismiss)
            Task { await onRefresh() }
        }) { sheet in
            switch sheet {
            case .addCategory:
                CategoryFormSheet(category: nil) { await onRefresh() }
            case .addStyle(let catId):
                StyleFormSheet(style: nil, categoryId: catId) { await onRefresh() }
            case .addType(let styleId):
                TypeFormSheet(type: nil, styleId: styleId) { await onRefresh() }
            case .addColor:
                ColorFormSheet(color: nil) { await onRefresh() }
            case .help:
                HierarchyHelpView()
            case .editColorPrice(let colorId, let typeId):
                CascadePriceEditSheet(colorId: colorId, typeId: typeId) {
                    loadColorPrices()
                }
            case .pricingOverride:
                PricingTierSetSheet {
                    loadColorPrices()
                }
            }
        }
        .task { loadColorPrices() }
    }

    // MARK: - Price Loading

    /// Load effective cost for every color in the hierarchy into the cache.
    private func loadColorPrices() {
        guard let parts = appCore.partsService else {
            colorPriceError = "Parts service unavailable"
            return
        }
        colorPriceError = nil
        var cache: [Int64: Double?] = [:]
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    let typeId = typeNode.type.id ?? 0
                    for brandNode in typeNode.brandNodes {
                        for color in brandNode.colors {
                            let colorId = color.id ?? 0
                            do {
                                let resolved = try parts.getEffectivePrice(colorId: colorId, typeId: typeId)
                                cache[colorId] = resolved.effectiveCost
                            } catch {
                                // Price resolution failed for this color; skip silently in cache build
                            }
                        }
                    }
                }
            }
        }
        colorPriceCache = cache
    }

    // MARK: - Filtered Hierarchy

    /// Filters the hierarchy tree to only show nodes matching the search query.
    /// When a child matches, all its ancestors are included to preserve the tree path.
    private var filteredCategories: [PartsService.CategoryNode] {
        guard !searchText.isEmpty else { return hierarchy.categories }
        let query = searchText.lowercased()

        return hierarchy.categories.compactMap { catNode -> PartsService.CategoryNode? in
            let catMatches = catNode.category.name.lowercased().contains(query)

            let filteredStyles = catNode.styles.compactMap { styleNode -> PartsService.StyleNode? in
                let styleMatches = styleNode.style.name.lowercased().contains(query)

                let filteredTypes = styleNode.types.compactMap { typeNode -> PartsService.TypeNode? in
                    let typeMatches = typeNode.type.name.lowercased().contains(query)

                    let hasBrandMatch = typeNode.brandNodes.contains { brandNode in
                        brandNode.name.lowercased().contains(query) ||
                        brandNode.colors.contains { $0.name.lowercased().contains(query) }
                    }

                    if typeMatches || hasBrandMatch {
                        return typeNode
                    }
                    return nil
                }

                if styleMatches || !filteredTypes.isEmpty {
                    return PartsService.StyleNode(
                        style: styleNode.style,
                        types: filteredTypes.isEmpty && styleMatches ? styleNode.types : filteredTypes
                    )
                }
                return nil
            }

            if catMatches || !filteredStyles.isEmpty {
                return PartsService.CategoryNode(
                    category: catNode.category,
                    styles: filteredStyles.isEmpty && catMatches ? catNode.styles : filteredStyles
                )
            }
            return nil
        }
    }

    // MARK: - Category Level

    @ViewBuilder
    private func categorySection(_ catNode: PartsService.CategoryNode) -> some View {
        let catId = catNode.category.id ?? 0
        let isSelected = selection == .category(catId)
        let isExpanded = expandedCategories.contains(catId)

        VStack(alignment: .leading, spacing: 0) {
            // Tappable row — selects AND toggles expand
            HStack(spacing: DS.Space.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                treeRow(
                    icon: "folder.fill",
                    iconColor: .accentColor,
                    title: catNode.category.name,
                    subtitle: "\(catNode.styles.count) style\(catNode.styles.count == 1 ? "" : "s")",
                    isSelected: isSelected,
                    badgeCount: isExpanded ? nil : catNode.styles.count
                )
            }
            .padding(.leading, DS.Space.lg)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .category(catId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(catId)
                    } else {
                        expandedCategories.insert(catId)
                    }
                }
            }
            .accessibilityIdentifier("categoryRow_\(catId)")
            .contextMenu {
                // Fix #229: gate pricing override behind edit_pricing permission.
                // Without this guard, any user with read access to the catalog tree
                // could open PricingOverrideFlow and overwrite tiers.
                if appCore.hasPermission("edit_pricing") {
                    Button {
                        activeSheet = .pricingOverride
                    } label: {
                        Label("Set Pricing Override", systemImage: "dollarsign.circle")
                    }
                }
            }

            // Children (styles)
            if isExpanded {
                ForEach(catNode.styles, id: \.style.id) { styleNode in
                    styleSection(styleNode, categoryId: catId)
                }

                // Add Style button
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
                .padding(.leading, DS.Space.lg + DS.Space.xl + 14)
                .padding(.vertical, DS.Space.xs)
                .accessibilityIdentifier("addStyleButton_\(catId)")
            }
        }
    }

    // MARK: - Style Level

    @ViewBuilder
    private func styleSection(_ styleNode: PartsService.StyleNode, categoryId: Int64) -> some View {
        let styleId = styleNode.style.id ?? 0
        let isSelected = selection == .style(styleId)
        let isExpanded = expandedStyles.contains(styleId)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                treeRow(
                    icon: "paintbrush.fill",
                    iconColor: .purple,
                    title: styleNode.style.name,
                    subtitle: "\(styleNode.types.count) type\(styleNode.types.count == 1 ? "" : "s")",
                    isSelected: isSelected,
                    badgeCount: isExpanded ? nil : styleNode.types.count
                )
            }
            .padding(.leading, DS.Space.lg + DS.Space.lg)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .style(styleId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedStyles.remove(styleId)
                    } else {
                        expandedStyles.insert(styleId)
                    }
                }
            }

            // Children (types)
            if isExpanded {
                ForEach(styleNode.types, id: \.type.id) { typeNode in
                    typeSection(typeNode)
                }

                // Add Type button
                Button {
                    activeSheet = .addType(styleId)
                } label: {
                    Label("Add Type", systemImage: "plus.circle.fill")
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
                .padding(.leading, DS.Space.lg + DS.Space.lg + DS.Space.xl + 14)
                .padding(.vertical, DS.Space.xs)
            }
        }
    }

    // MARK: - Type Level

    @ViewBuilder
    private func typeSection(_ typeNode: PartsService.TypeNode) -> some View {
        let typeId = typeNode.type.id ?? 0
        let isSelected = selection == .type(typeId)
        let isExpanded = expandedTypes.contains(typeId)
        let brandCount = typeNode.brandNodes.filter({ !$0.isGeneral }).count
        let colorCount = typeNode.totalColorCount

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                treeRow(
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: .teal,
                    title: typeNode.type.name,
                    subtitle: "\(brandCount) brand\(brandCount == 1 ? "" : "s"), \(colorCount) color\(colorCount == 1 ? "" : "s")",
                    isSelected: isSelected,
                    badgeCount: isExpanded ? nil : typeNode.brandNodes.count
                )
            }
            .padding(.leading, DS.Space.lg + DS.Space.lg + DS.Space.lg)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .type(typeId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedTypes.remove(typeId)
                    } else {
                        expandedTypes.insert(typeId)
                    }
                }
            }
            .contextMenu {
                // Fix #229: gate pricing override behind edit_pricing permission (type-row variant).
                if appCore.hasPermission("edit_pricing") {
                    Button {
                        activeSheet = .pricingOverride
                    } label: {
                        Label("Set Pricing Override", systemImage: "dollarsign.circle")
                    }
                }
            }

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
        }
    }

    // MARK: - Brand Level (under Type)

    @ViewBuilder
    private func brandSection(_ brandNode: PartsService.BrandNode, typeId: Int64) -> some View {
        let brandId = brandNode.id  // -1 for General
        let realBrandId = brandNode.brand?.id
        let skuCacheKey = skuKey(typeId: typeId, brandId: realBrandId ?? 0)
        let brandSKUs = realBrandId.map { skuCache[skuKey(typeId: typeId, brandId: $0)] ?? [] } ?? []
        let childCount = brandNode.colors.count + brandSKUs.count
        let isSelected: Bool = {
            if brandNode.isGeneral {
                return selection == .brand(brandId: 0, typeId: typeId)
            } else {
                return selection == .brand(brandId: brandNode.brand?.id ?? 0, typeId: typeId)
            }
        }()
        let isExpanded = expandedBrands.contains(brandId)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                if childCount > 0 {
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
                    subtitle: brandSubtitle(colorCount: brandNode.colors.count, skuCount: brandSKUs.count),
                    isSelected: isSelected
                )
            }
            .padding(.leading, DS.Space.lg * 3 + 14)
            .task(id: skuCacheKey) {
                if let realBrandId {
                    await loadSKUs(typeId: typeId, brandId: realBrandId)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let brand = brandNode.brand {
                    selection = .brand(brandId: brand.id ?? 0, typeId: typeId)
                } else {
                    selection = .brand(brandId: 0, typeId: typeId) // General
                }
                if childCount > 0 {
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
                if let error = skuLoadErrors[skuCacheKey] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, DS.Space.lg * 4 + 14)
                        .padding(.vertical, DS.Space.xs)
                }
                if let realBrandId {
                    if skuCache[skuCacheKey] == nil {
                        ProgressView("Loading SKU rows…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, DS.Space.lg * 4 + 14)
                            .padding(.vertical, DS.Space.xs)
                    } else if brandSKUs.isEmpty {
                        ContentUnavailableView {
                            Label("No SKU Rows Yet", systemImage: "barcode.viewfinder")
                        } description: {
                            Text("This type/brand pair has no SKU rows yet.")
                        }
                        .padding(.leading, DS.Space.lg * 4 + 14)
                        .padding(.vertical, DS.Space.xs)
                        .accessibilityIdentifier("emptySKURows_\(typeId)_\(realBrandId)")
                    }
                }
                ForEach(brandSKUs, id: \.id) { sku in
                    skuRow(sku, brandName: brandNode.name, typeId: typeId)
                }
                ForEach(brandNode.colors, id: \.id) { color in
                    colorRow(color, typeId: typeId, brandId: brandNode.brand?.id)
                }
            }
        }
    }

    private func skuKey(typeId: Int64, brandId: Int64) -> String {
        "\(typeId):\(brandId)"
    }

    private func brandSubtitle(colorCount: Int, skuCount: Int) -> String {
        if skuCount > 0 {
            return "\(skuCount) SKU\(skuCount == 1 ? "" : "s"), \(colorCount) color\(colorCount == 1 ? "" : "s")"
        }
        return "\(colorCount) color\(colorCount == 1 ? "" : "s")"
    }

    private func loadSKUs(typeId: Int64, brandId: Int64) async {
        let key = skuKey(typeId: typeId, brandId: brandId)
        guard skuCache[key] == nil else { return }
        guard let parts = appCore.partsService else {
            skuLoadErrors[key] = "Parts service unavailable"
            return
        }
        do {
            let skus = try parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
            skuCache[key] = skus
            skuLoadErrors[key] = nil
        } catch {
            skuCache[key] = []
            skuLoadErrors[key] = "Failed to load SKU rows"
        }
    }

    private func colorForSKU(_ sku: PartsService.ColorBrandSKU) -> PartColor? {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    if let color = typeNode.colors.first(where: { $0.id == sku.colorId }) {
                        return color
                    }
                    for brandNode in typeNode.brandNodes {
                        if let color = brandNode.colors.first(where: { $0.id == sku.colorId }) {
                            return color
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - SKU Row (color_brand_skus, under Type × Brand)

    @ViewBuilder
    private func skuRow(_ sku: PartsService.ColorBrandSKU, brandName: String, typeId: Int64) -> some View {
        let isSelected = selection == .sku(skuId: sku.id, typeId: typeId, brandId: sku.brandId, colorId: sku.colorId)
        let color = colorForSKU(sku)

        HStack(spacing: DS.Space.sm) {
            variantChip(color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Space.xs) {
                    Text(color?.name ?? "Variant #\(sku.colorId)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(brandName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.14))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                Text((sku.partNumber?.isEmpty == false) ? "PN: \(sku.partNumber!)" : "No SKU part number")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer()

            if let cost = sku.unitCost {
                Text(cost, format: .currency(code: "USD"))
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            Text("Qty \(sku.stockQty)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.lg)
        .padding(.leading, DS.Space.lg * 4 + 14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .sku(skuId: sku.id, typeId: typeId, brandId: sku.brandId, colorId: sku.colorId)
        }
        .accessibilityIdentifier("skuRow_\(sku.id)")
    }

    @ViewBuilder
    private func variantChip(_ color: PartColor?) -> some View {
        let name = color?.name ?? "SKU"
        if let hex = color?.hexCode, !hex.isEmpty, let resolved = Color(hex: hex) {
            Text(name)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(resolved.opacity(0.22))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        } else {
            Text(name)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(.secondarySystemGroupedBackground))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Color Row (Level 5, under Brand)

    @ViewBuilder
    private func colorRow(_ color: PartColor, typeId: Int64, brandId: Int64? = nil) -> some View {
        let colorId = color.id ?? 0
        let isSelected = selection == .color(colorId: colorId, typeId: typeId, brandId: brandId)

        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(Color(hex: color.hexCode ?? "#888888") ?? .gray)
                .frame(width: 14, height: 14)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 2) {
                Text(color.name)
                    .font(.subheadline)
                if let pn = color.partNumber, !pn.isEmpty {
                    Text("PN: \(pn)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No part number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()

            // Pricing chip — tap to edit
            Button {
                activeSheet = .editColorPrice(colorId: colorId, typeId: typeId)
            } label: {
                if let cached = colorPriceCache[colorId], let cost = cached {
                    Text(cost, format: .currency(code: "USD"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else {
                    Text("No price")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit price")
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.lg)
        .padding(.leading, DS.Space.lg * 4 + 14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .color(colorId: colorId, typeId: typeId, brandId: brandId)
        }
    }

    // MARK: - Shared Row Builder

    @ViewBuilder
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

    // MARK: - Count Badge

    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.8)))
    }
}

// MARK: - Hierarchy Help View

struct HierarchyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    // Overview
                    Text("How the Parts Hierarchy Works")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Parts are organized in a 5-level tree. Each level adds specificity:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Level explanations
                    hierarchyLevel(
                        number: 1,
                        name: "Category",
                        icon: "folder.fill",
                        color: .accentColor,
                        example: "e.g. Electrical, Plumbing, Framing",
                        description: "The broadest grouping. Start here."
                    )

                    hierarchyLevel(
                        number: 2,
                        name: "Style",
                        icon: "paintbrush.fill",
                        color: .purple,
                        example: "e.g. Residential, Commercial, Industrial",
                        description: "A variation within a category. Different styles may use different types of parts."
                    )

                    hierarchyLevel(
                        number: 3,
                        name: "Type",
                        icon: "wrench.and.screwdriver.fill",
                        color: .teal,
                        example: "e.g. 12/2 Wire, 14/2 Wire, THHN",
                        description: "The specific kind of part. This is where you link brands and colors."
                    )

                    hierarchyLevel(
                        number: 4,
                        name: "Brand",
                        icon: "tag.fill",
                        color: .orange,
                        example: "e.g. Southwire, Cerro, General",
                        description: "Which manufacturer makes this type. 'General' means no specific brand."
                    )

                    hierarchyLevel(
                        number: 5,
                        name: "Color",
                        icon: "circle.fill",
                        color: .pink,
                        example: "e.g. White, Black, Red, None",
                        description: "The color variant. Selecting a color under a brand creates a catalog entry you can order and stock."
                    )

                    Divider()

                    // Quick start
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Quick Start")
                            .font(.headline)

                        stepRow(step: 1, text: "Tap the **+** button to create a Category")
                        stepRow(step: 2, text: "Tap into the category and add a **Style**")
                        stepRow(step: 3, text: "Add a **Type** under the style")
                        stepRow(step: 4, text: "Link **Brands** to the type using checkboxes")
                        stepRow(step: 5, text: "Pick **Colors** under each brand to create catalog entries")
                    }

                    Divider()

                    Text("Each catalog entry (Type + Brand + Color) becomes a part you can order, stock, and track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
            }
            .navigationTitle("Hierarchy Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func hierarchyLevel(number: Int, name: String, icon: String, color: Color, example: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            // Level indicator
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                Text("\(number)")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.subheadline)
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(example)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        // Indent each level slightly more
        .padding(.leading, CGFloat(number - 1) * 8)
    }

    @ViewBuilder
    private func stepRow(step: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Text("\(step).")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Sheet ID helpers

extension Int64: @retroactive Identifiable {
    public var id: Int64 { self }
}
