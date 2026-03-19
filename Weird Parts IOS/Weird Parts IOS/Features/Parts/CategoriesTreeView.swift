import SwiftUI
import WiredPartCore

/// Enum representing which node in the hierarchy tree is selected.
enum TreeSelection: Equatable {
    case category(Int64)
    case style(Int64)
    case type(Int64)
    case brand(brandId: Int64, typeId: Int64)
    case color(colorId: Int64, typeId: Int64, brandId: Int64?)
}

/// Left-panel tree browser: 5-level nested hierarchy showing
/// Category > Style > Type > Brand > Color.
///
/// Uses manual expand/collapse state so that tapping a row
/// both **selects** it AND **expands/collapses** its children.
struct CategoriesTreeView: View {
    let hierarchy: PartsService.HierarchyTree
    @Binding var selection: TreeSelection?

    // Manual expand/collapse state per level
    @State private var expandedCategories: Set<Int64> = []
    @State private var expandedStyles: Set<Int64> = []
    @State private var expandedTypes: Set<Int64> = []

    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addCategory
        case addStyle(Int64)
        case addType(Int64)
        case addColor

        var id: String {
            switch self {
            case .addCategory: return "addCategory"
            case .addStyle(let id): return "addStyle-\(id)"
            case .addType(let id): return "addType-\(id)"
            case .addColor: return "addColor"
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
                Spacer()
                Menu {
                    Button { activeSheet = .addCategory } label: {
                        Label("New Category", systemImage: "folder.badge.plus")
                    }
                    Button { activeSheet = .addColor } label: {
                        Label("New Color", systemImage: "paintpalette")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)

            Divider()

            if hierarchy.categories.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.questionmark",
                    title: "No Categories Yet",
                    message: "Create categories to organize your parts hierarchy.",
                    actionLabel: "Add Category"
                ) {
                    activeSheet = .addCategory
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hierarchy.categories) { catNode in
                            categorySection(catNode)
                        }
                    }
                    .padding(.vertical, DS.Space.sm)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addCategory:
                CategoryFormSheet(category: nil) { await onRefresh() }
            case .addStyle(let catId):
                StyleFormSheet(style: nil, categoryId: catId) { await onRefresh() }
            case .addType(let styleId):
                TypeFormSheet(type: nil, styleId: styleId) { await onRefresh() }
            case .addColor:
                ColorFormSheet(color: nil) { await onRefresh() }
            }
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
                    isSelected: isSelected
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

            // Children (styles)
            if isExpanded {
                ForEach(catNode.styles, id: \.style.id) { styleNode in
                    styleSection(styleNode, categoryId: catId)
                }

                // Add Style button
                Button {
                    activeSheet = .addStyle(catId)
                } label: {
                    Label("Add Style", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, DS.Space.lg + DS.Space.xl + 14)
                .padding(.vertical, DS.Space.xs)
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
                    isSelected: isSelected
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
                    Label("Add Type", systemImage: "plus")
                        .font(.caption)
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
        let hasChildren = !typeNode.brands.isEmpty || !typeNode.colors.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                } else {
                    // Leaf indicator — no chevron, just spacing
                    Color.clear.frame(width: 14)
                }

                treeRow(
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: .teal,
                    title: typeNode.type.name,
                    subtitle: "\(typeNode.brands.count) brand\(typeNode.brands.count == 1 ? "" : "s"), \(typeNode.colors.count) color\(typeNode.colors.count == 1 ? "" : "s")",
                    isSelected: isSelected
                )
            }
            .padding(.leading, DS.Space.lg + DS.Space.lg + DS.Space.lg)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = .type(typeId)
                if hasChildren {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedTypes.remove(typeId)
                        } else {
                            expandedTypes.insert(typeId)
                        }
                    }
                }
            }

            // Children (brands + colors)
            if isExpanded {
                if !typeNode.brands.isEmpty {
                    ForEach(typeNode.brands, id: \.id) { brand in
                        brandRow(brand, typeId: typeId)
                    }
                }

                if !typeNode.colors.isEmpty {
                    ForEach(typeNode.colors, id: \.id) { color in
                        colorRow(color, typeId: typeId)
                    }
                }

                if typeNode.brands.isEmpty && typeNode.colors.isEmpty {
                    Text("No brands or colors linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, DS.Space.lg * 4 + DS.Space.xl)
                        .padding(.vertical, DS.Space.xs)
                }
            }
        }
    }

    // MARK: - Brand Row (Level 4)

    @ViewBuilder
    private func brandRow(_ brand: Brand, typeId: Int64) -> some View {
        let brandId = brand.id ?? 0
        let isSelected = selection == .brand(brandId: brandId, typeId: typeId)

        HStack(spacing: DS.Space.sm) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(brand.name)
                .font(.subheadline)
            Spacer()
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.lg)
        .padding(.leading, DS.Space.lg * 3 + 14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .brand(brandId: brandId, typeId: typeId)
        }
    }

    // MARK: - Color Row (Level 5)

    @ViewBuilder
    private func colorRow(_ color: PartColor, typeId: Int64) -> some View {
        let colorId = color.id ?? 0
        let isSelected = selection == .color(colorId: colorId, typeId: typeId, brandId: nil)

        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(Color(hex: color.hexCode ?? "#888888") ?? .gray)
                .frame(width: 14, height: 14)
            Text(color.name)
                .font(.subheadline)
            Spacer()
            if let hex = color.hexCode {
                Text(hex)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.lg)
        .padding(.leading, DS.Space.lg * 3 + 14)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .color(colorId: colorId, typeId: typeId, brandId: nil)
        }
    }

    // MARK: - Shared Row Builder

    @ViewBuilder
    private func treeRow(icon: String, iconColor: Color, title: String, subtitle: String, isSelected: Bool) -> some View {
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
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.trailing, DS.Space.sm)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Sheet ID helpers

extension Int64: @retroactive Identifiable {
    public var id: Int64 { self }
}
