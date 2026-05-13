import SwiftUI
import WiredPartCore

/// Enum representing which node in the hierarchy tree is selected.
enum TreeSelection: Equatable {
    case category(Int64)
    case style(Int64)
    case type(Int64)
    case brand(brandId: Int64, typeId: Int64)
    case color(colorId: Int64, typeId: Int64, brandId: Int64?)
    case sku(skuId: Int64, colorId: Int64, typeId: Int64, brandId: Int64)
}

/// Left-panel tree browser showing Category > Style > Type > Variant > SKU.
///
/// Brands are SKU attributes in this view, not owners of variants.
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
    @Binding var expandedVariants: Set<Int64>
    @State private var searchText = ""

    /// Cache of effective cost per colorId, loaded alongside hierarchy.
    @State private var colorPriceCache: [Int64: Double?] = [:]
    @State private var skuCache: [Int64: [PartsService.ColorBrandSKU]] = [:]
    @State private var skuLoadingTypeIds: Set<Int64> = []

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
                        Label("New Variant", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("addColorMenuItem")
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityIdentifier("categoriesAddMenu")
                .accessibilityLabel("Add category or variant")
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
                TextField("Search categories, variants, brands...", text: $searchText)
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

                        Text("The parts hierarchy organizes inventory as:\nCategory > Style > Type > Variant > SKU")
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
        guard let parts = appCore.partsService else { return }
        var cache: [Int64: Double?] = [:]
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    let typeId = typeNode.type.id ?? 0
                    for color in typeNode.colors {
                        let colorId = color.id ?? 0
                        do {
                            let resolved = try parts.getEffectivePrice(colorId: colorId, typeId: typeId)
                            cache[colorId] = resolved.effectiveCost
                        } catch {
                            // Price resolution failed for this variant; skip silently in cache build
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

                    let hasBrandMatch = typeNode.brands.contains { $0.name.lowercased().contains(query) }
                    let hasVariantMatch = typeNode.colors.contains { $0.name.lowercased().contains(query) }

                    if typeMatches || hasBrandMatch || hasVariantMatch {
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
        let brandCount = typeNode.brands.count
        let variantCount = typeNode.colors.count

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
                    subtitle: "\(variantCount) variant\(variantCount == 1 ? "" : "s"), \(brandCount) brand\(brandCount == 1 ? "" : "s")",
                    isSelected: isSelected,
                    badgeCount: isExpanded ? nil : variantCount
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

            // Children (variants, with brand-specific SKU rows underneath)
            if isExpanded {
                ForEach(typeNode.colors, id: \.id) { color in
                    variantSection(color, typeNode: typeNode)
                }

                if typeNode.colors.isEmpty {
                    Text("No variants linked yet - add variants from the type editor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, DS.Space.lg * 4 + DS.Space.xl)
                        .padding(.vertical, DS.Space.xs)
                }
            }
        }
    }

    // MARK: - Variant Level (under Type)

    @ViewBuilder
    private func variantSection(_ color: PartColor, typeNode: PartsService.TypeNode) -> some View {
        let typeId = typeNode.type.id ?? 0
        let colorId = color.id ?? 0
        let isSelected = selection == .color(colorId: colorId, typeId: typeId, brandId: nil)
        let isExpanded = expandedVariants.contains(colorId)
        let skuCount = skuCache[typeId]?.filter { $0.colorId == colorId }.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                if skuCount != 0 {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }

                treeRow(
                    icon: "circle.hexagongrid.fill",
                    iconColor: .pink,
                    title: color.name,
                    subtitle: skuCount.map { "\($0) SKU\($0 == 1 ? "" : "s")" } ?? "Loading SKUs",
                    isSelected: isSelected,
                    badgeCount: isExpanded ? nil : skuCount
                )
            }
            .padding(.leading, DS.Space.lg * 3 + 14)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .color(colorId: colorId, typeId: typeId, brandId: nil)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedVariants.remove(colorId)
                    } else {
                        expandedVariants.insert(colorId)
                    }
                }
            }

            if isExpanded {
                skuRows(typeNode: typeNode, color: color)
            }
        }
        .task {
            loadSKUsIfNeeded(typeId: typeId)
        }
    }

    // MARK: - SKU Rows (under Variant)

    @ViewBuilder
    private func skuRows(typeNode: PartsService.TypeNode, color: PartColor) -> some View {
        let typeId = typeNode.type.id ?? 0
        let colorId = color.id ?? 0
        let rows = (skuCache[typeId] ?? []).filter { $0.colorId == colorId }

        Group {
            if skuLoadingTypeIds.contains(typeId) && rows.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    ProgressView()
                    Text("Loading SKUs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.Space.xs)
                .padding(.leading, DS.Space.lg * 4 + 14)
            } else if rows.isEmpty {
                Text("No brand-specific SKU rows yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.xs)
                    .padding(.leading, DS.Space.lg * 4 + 14)
            } else {
                ForEach(rows, id: \.id) { sku in
                    skuRow(sku, color: color, brandName: brandName(for: sku.brandId, in: typeNode))
                }
            }
        }
    }

    @ViewBuilder
    private func skuRow(_ sku: PartsService.ColorBrandSKU, color: PartColor, brandName: String) -> some View {
        let isSelected = selection == .sku(
            skuId: sku.id,
            colorId: sku.colorId,
            typeId: sku.typeId,
            brandId: sku.brandId
        )

        HStack(spacing: DS.Space.sm) {
            variantChip(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.xs) {
                    Text(brandName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Text("SKU")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let pn = sku.partNumber, !pn.isEmpty {
                    Text(pn)
                        .font(.subheadline)
                        .monospaced()
                } else {
                    Text("No SKU part number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            if sku.stockQty > 0 {
                Text("\(sku.stockQty) on hand")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.lg)
        .padding(.leading, DS.Space.lg * 4 + 14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .sku(
                skuId: sku.id,
                colorId: sku.colorId,
                typeId: sku.typeId,
                brandId: sku.brandId
            )
        }
    }

    // MARK: - Variant Row

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

    private func loadSKUsIfNeeded(typeId: Int64) {
        guard skuCache[typeId] == nil, !skuLoadingTypeIds.contains(typeId), let parts = appCore.partsService else { return }
        skuLoadingTypeIds.insert(typeId)
        Task.detached {
            let rows = (try? parts.getSKUsForType(typeId: typeId)) ?? []
            await MainActor.run {
                skuCache[typeId] = rows
                skuLoadingTypeIds.remove(typeId)
            }
        }
    }

    private func brandName(for brandId: Int64, in typeNode: PartsService.TypeNode) -> String {
        typeNode.brands.first(where: { $0.id == brandId })?.name ?? "Brand #\(brandId)"
    }

    private func findColor(_ colorId: Int64) -> PartColor? {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    for color in typeNode.colors where color.id == colorId {
                        return color
                    }
                }
            }
        }
        return nil
    }

    @ViewBuilder
    private func variantChip(_ color: PartColor) -> some View {
        if let hex = color.hexCode, !hex.isEmpty, let resolved = Color(hex: hex) {
            HStack(spacing: 5) {
                Circle()
                    .fill(resolved)
                    .frame(width: 10, height: 10)
                Text(color.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
        } else {
            Text(color.name)
                .font(.caption2)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
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

                    Text("Parts are organized from broad category to reusable variant, then specific SKU:")
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
                        description: "The specific kind of part. This is where you link brands and reusable variants."
                    )

                    hierarchyLevel(
                        number: 4,
                        name: "Variant",
                        icon: "circle.hexagongrid.fill",
                        color: .pink,
                        example: "e.g. White, Black, Red, None",
                        description: "A reusable option for the type. Variants are shared and are not owned by a brand."
                    )

                    hierarchyLevel(
                        number: 5,
                        name: "SKU",
                        icon: "number.square.fill",
                        color: .orange,
                        example: "e.g. Southwire 28827401",
                        description: "The brand-specific purchasable row for a variant, with its own part number and cost."
                    )

                    Divider()

                    // Quick start
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Quick Start")
                            .font(.headline)

                        stepRow(step: 1, text: "Tap the **+** button to create a Category")
                        stepRow(step: 2, text: "Tap into the category and add a **Style**")
                        stepRow(step: 3, text: "Add a **Type** under the style")
                        stepRow(step: 4, text: "Link **Brands** and **Variants** to the type")
                        stepRow(step: 5, text: "Edit **SKU** rows when a brand has a specific part number or cost")
                    }

                    Divider()

                    Text("Brand deferral belongs in ordering flows, not in the Categories structure.")
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
