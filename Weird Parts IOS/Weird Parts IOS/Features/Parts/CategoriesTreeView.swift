import SwiftUI
import OSLog
import WiredPartCore

private let categoryPriceLog = Logger(subsystem: "com.wiredpart.ios", category: "CategoriesTreeView")

/// Enum representing which node in the hierarchy tree is selected.
enum TreeSelection: Equatable {
    case category(Int64)
    case style(Int64)
    case type(Int64)
    case brand(brandId: Int64, typeId: Int64)
    case color(colorId: Int64, typeId: Int64, brandId: Int64?)
}

enum ColorPriceCacheEntry: Equatable {
    case resolved(Double?)
    case unavailable
}

enum ColorPriceChipState: Equatable {
    case loading
    case priced(Double)
    case unpriced
    case unavailable
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
    @State private var colorPriceCache: [Int64: ColorPriceCacheEntry] = [:]
    @State private var priceLoadError: String?

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

            if let priceLoadError {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(priceLoadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.xs)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
            priceLoadError = "Pricing unavailable: parts service is not ready."
            colorPriceCache = unavailablePriceCache(for: hierarchy)
            categoryPriceLog.error("Color price cache unavailable: parts service missing")
            return
        }

        var cache: [Int64: ColorPriceCacheEntry] = [:]
        var failedLookups = 0
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    let typeId = typeNode.type.id ?? 0
                    for brandNode in typeNode.brandNodes {
                        for color in brandNode.colors {
                            let colorId = color.id ?? 0
                            do {
                                let resolved = try parts.getEffectivePrice(colorId: colorId, typeId: typeId)
                                cache[colorId] = .resolved(resolved.effectiveCost)
                            } catch {
                                cache[colorId] = .unavailable
                                failedLookups += 1
                                categoryPriceLog.error("Color price resolution failed colorId=\(colorId, privacy: .public) typeId=\(typeId, privacy: .public): \(String(describing: error), privacy: .public)")
                            }
                        }
                    }
                }
            }
        }
        priceLoadError = failedLookups > 0 ? "Some color prices could not be resolved." : nil
        colorPriceCache = cache
    }

    private func unavailablePriceCache(for hierarchy: PartsService.HierarchyTree) -> [Int64: ColorPriceCacheEntry] {
        var cache: [Int64: ColorPriceCacheEntry] = [:]
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    for brandNode in typeNode.brandNodes {
                        for color in brandNode.colors {
                            if let colorId = color.id {
                                cache[colorId] = .unavailable
                            }
                        }
                    }
                }
            }
        }
        return cache
    }

    static func priceChipState(for colorId: Int64, cache: [Int64: ColorPriceCacheEntry]) -> ColorPriceChipState {
        guard let cached = cache[colorId] else { return .loading }
        switch cached {
        case .resolved(let cost):
            if let cost { return .priced(cost) }
            return .unpriced
        case .unavailable:
            return .unavailable
        }
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
                if !brandNode.colors.isEmpty {
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
                    subtitle: "\(brandNode.colors.count) color\(brandNode.colors.count == 1 ? "" : "s")",
                    isSelected: isSelected
                )
            }
            .padding(.leading, DS.Space.lg * 3 + 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if let brand = brandNode.brand {
                    selection = .brand(brandId: brand.id ?? 0, typeId: typeId)
                } else {
                    selection = .brand(brandId: 0, typeId: typeId) // General
                }
                if !brandNode.colors.isEmpty {
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
                ForEach(brandNode.colors, id: \.id) { color in
                    colorRow(color, typeId: typeId, brandId: brandNode.brand?.id)
                }
            }
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
                switch Self.priceChipState(for: colorId, cache: colorPriceCache) {
                case .priced(let cost):
                    Text(cost, format: .currency(code: "USD"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                case .unpriced:
                    Text("No price")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                case .unavailable:
                    Label("Price unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.10))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                case .loading:
                    Text("Loading price")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.12))
                        .foregroundStyle(.secondary)
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
