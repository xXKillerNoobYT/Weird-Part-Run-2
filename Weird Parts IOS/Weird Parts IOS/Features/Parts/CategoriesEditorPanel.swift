import SwiftUI
import WiredPartCore

/// Left-panel editor that shows the appropriate editing UI
/// based on which node is selected in the tree.
struct CategoriesEditorPanel: View {
    let selection: TreeSelection?
    let hierarchy: PartsService.HierarchyTree
    var onRefresh: () async -> Void

    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        Group {
            if let selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        editorContent(for: selection)
                    }
                    .padding(DS.Space.lg)
                }
            } else {
                emptySelection
            }
        }
        .sheet(item: $addStyleCategoryId) { catId in
            StyleFormSheet(style: nil, categoryId: catId) { await onRefresh() }
        }
        .sheet(item: $addTypeStyleId) { styleId in
            TypeFormSheet(type: nil, styleId: styleId) { await onRefresh() }
        }
        .sheet(isPresented: $showAddColor) {
            ColorFormSheet(color: nil) { await onRefresh() }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptySelection: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Image(systemName: "sidebar.squares.left")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select an Item")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Tap a category, style, type, brand, or color in the tree to view and edit its details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.xxxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Router

    @ViewBuilder
    private func editorContent(for selection: TreeSelection) -> some View {
        switch selection {
        case .category(let catId):
            categoryEditor(catId: catId)
        case .style(let styleId):
            styleEditor(styleId: styleId)
        case .type(let typeId):
            typeEditor(typeId: typeId)
        case .brand(let brandId, let typeId):
            brandEditor(brandId: brandId, typeId: typeId)
        case .color(let colorId, let typeId, let brandId):
            colorEditor(colorId: colorId, typeId: typeId, brandId: brandId)
        }
    }

    // MARK: - Category Editor

    @ViewBuilder
    private func categoryEditor(catId: Int64) -> some View {
        if let catNode = hierarchy.categories.first(where: { $0.category.id == catId }) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Label("Category", systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(catNode.category.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if let desc = catNode.category.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Stats
                HStack(spacing: DS.Space.xl) {
                    statPill(value: catNode.styles.count, label: "Styles")
                    let typeCount = catNode.styles.reduce(0) { $0 + $1.types.count }
                    statPill(value: typeCount, label: "Types")
                }

                Divider()

                // Actions
                HStack(spacing: DS.Space.md) {
                    editCategoryButton(catNode.category)
                    deleteCategoryButton(catId)
                }

                Divider()

                // Sub-items: Styles in this category
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text("Styles")
                            .font(.headline)
                        Spacer()
                        Button {
                            addStyleCategoryId = catId
                        } label: {
                            Label("Add Style", systemImage: "plus")
                                .font(.caption)
                        }
                    }

                    if catNode.styles.isEmpty {
                        Text("No styles yet. Add a style to start building this category.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, DS.Space.sm)
                    } else {
                        ForEach(catNode.styles) { styleNode in
                            HStack(spacing: DS.Space.sm) {
                                Image(systemName: "paintbrush.fill")
                                    .foregroundStyle(.purple)
                                    .font(.caption)
                                Text(styleNode.style.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(styleNode.types.count) type\(styleNode.types.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, DS.Space.xxs)
                        }
                    }
                }
            }
        } else {
            Text("Category not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Style Editor

    @ViewBuilder
    private func styleEditor(styleId: Int64) -> some View {
        if let (catNode, styleNode) = findStyle(styleId) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Label("Style", systemImage: "paintbrush.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(styleNode.style.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: DS.Space.xs) {
                    Text("in")
                        .foregroundStyle(.secondary)
                    Text(catNode.category.name)
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                if let desc = styleNode.style.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                statPill(value: styleNode.types.count, label: "Types")

                Divider()

                HStack(spacing: DS.Space.md) {
                    editStyleButton(styleNode.style)
                    deleteStyleButton(styleId)
                }

                Divider()

                // Sub-items: Types in this style
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text("Types")
                            .font(.headline)
                        Spacer()
                        Button {
                            addTypeStyleId = styleId
                        } label: {
                            Label("Add Type", systemImage: "plus")
                                .font(.caption)
                        }
                    }

                    if styleNode.types.isEmpty {
                        Text("No types yet. Add a type to continue building this style.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, DS.Space.sm)
                    } else {
                        ForEach(styleNode.types) { typeNode in
                            HStack(spacing: DS.Space.sm) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(.teal)
                                    .font(.caption)
                                Text(typeNode.type.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(typeNode.brands.count) brand\(typeNode.brands.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, DS.Space.xxs)
                        }
                    }
                }
            }
        } else {
            Text("Style not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Type Editor

    @ViewBuilder
    private func typeEditor(typeId: Int64) -> some View {
        if let (_, styleNode, typeNode) = findType(typeId) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Label("Type", systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(typeNode.type.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: DS.Space.xs) {
                    Text("in")
                        .foregroundStyle(.secondary)
                    Text(styleNode.style.name)
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                if let desc = typeNode.type.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: DS.Space.xl) {
                    statPill(value: typeNode.brands.count, label: "Brands")
                    statPill(value: typeNode.colors.count, label: "Colors")
                }

                Divider()

                HStack(spacing: DS.Space.md) {
                    editTypeButton(typeNode.type)
                    deleteTypeButton(typeId)
                }

                Divider()

                // Brand checkboxes section
                CategoriesBrandSection(typeId: typeId)

                Divider()

                // Color picker section
                CategoriesColorPicker(
                    typeId: typeId,
                    brandId: nil,
                    hierarchy: hierarchy,
                    onRefresh: onRefresh
                )

                Divider()

                // Add color shortcut
                Button {
                    showAddColor = true
                } label: {
                    Label("Create New Color", systemImage: "paintpalette")
                }
                .buttonStyle(.bordered)
            }
        } else {
            Text("Type not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Brand Editor

    @ViewBuilder
    private func brandEditor(brandId: Int64, typeId: Int64) -> some View {
        if let (_, _, typeNode) = findType(typeId) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Label("Brand", systemImage: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let brand = typeNode.brands.first(where: { $0.id == brandId }) {
                    Text(brand.name)
                        .font(.title2)
                        .fontWeight(.bold)
                } else {
                    Text("Brand")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                HStack(spacing: DS.Space.xs) {
                    Text("on type")
                        .foregroundStyle(.secondary)
                    Text(typeNode.type.name)
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                Divider()

                // Brand section focused on this specific brand
                CategoriesBrandSection(typeId: typeId, focusedBrandId: brandId)

                Divider()

                // Color picker for this brand — prominent section
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Label("Available Colors", systemImage: "paintpalette.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Pick a color below to create a catalog entry for this brand + type + color combination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CategoriesColorPicker(
                        typeId: typeId,
                        brandId: brandId,
                        hierarchy: hierarchy,
                        onRefresh: onRefresh
                    )
                }
            }
        } else {
            Text("Type not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Color Editor

    @ViewBuilder
    private func colorEditor(colorId: Int64, typeId: Int64, brandId: Int64?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Label("Color", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Find the color in the hierarchy
            if let color = findColor(colorId) {
                HStack(spacing: DS.Space.md) {
                    Circle()
                        .fill(Color(hex: color.hexCode ?? "#888888") ?? .gray)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text(color.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        if let hex = color.hexCode {
                            Text(hex)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                    }
                }

                Divider()

                Text("This color is linked to the type. Parts with this color combination appear in the catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Color not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Lookups

    private func findStyle(_ styleId: Int64) -> (PartsService.CategoryNode, PartsService.StyleNode)? {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                if styleNode.style.id == styleId {
                    return (catNode, styleNode)
                }
            }
        }
        return nil
    }

    private func findType(_ typeId: Int64) -> (PartsService.CategoryNode, PartsService.StyleNode, PartsService.TypeNode)? {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    if typeNode.type.id == typeId {
                        return (catNode, styleNode, typeNode)
                    }
                }
            }
        }
        return nil
    }

    private func findColor(_ colorId: Int64) -> PartColor? {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    for color in typeNode.colors {
                        if color.id == colorId {
                            return color
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Action Buttons

    @State private var editingCategory: PartCategory?
    @State private var editingStyle: PartStyle?
    @State private var editingType: PartType?
    @State private var showDeleteConfirm = false
    @State private var deleteAction: (() async -> Void)?

    // Sub-item creation sheet triggers
    @State private var addStyleCategoryId: Int64?
    @State private var addTypeStyleId: Int64?
    @State private var showAddColor = false

    @ViewBuilder
    private func editCategoryButton(_ category: PartCategory) -> some View {
        Button {
            editingCategory = category
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .sheet(item: $editingCategory) { cat in
            CategoryFormSheet(category: cat) { await onRefresh() }
        }
    }

    @ViewBuilder
    private func deleteCategoryButton(_ catId: Int64) -> some View {
        Button(role: .destructive) {
            deleteAction = {
                guard let service = appCore.partsService else { return }
                do {
                    try service.deleteCategory(id: catId)
                    await onRefresh()
                } catch {
                    print("[EditorPanel] Delete category error: \(error)")
                }
            }
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .alert("Delete Category?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let action = deleteAction {
                    Task { await action() }
                }
            }
        } message: {
            Text("This will soft-delete the category. Styles and types under it will remain but become orphaned.")
        }
    }

    @ViewBuilder
    private func editStyleButton(_ style: PartStyle) -> some View {
        Button {
            editingStyle = style
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .sheet(item: $editingStyle) { s in
            StyleFormSheet(style: s, categoryId: s.categoryId) { await onRefresh() }
        }
    }

    @ViewBuilder
    private func deleteStyleButton(_ styleId: Int64) -> some View {
        Button(role: .destructive) {
            deleteAction = {
                guard let service = appCore.partsService else { return }
                do {
                    try service.deleteStyle(id: styleId)
                    await onRefresh()
                } catch {
                    print("[EditorPanel] Delete style error: \(error)")
                }
            }
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    @ViewBuilder
    private func editTypeButton(_ ptype: PartType) -> some View {
        Button {
            editingType = ptype
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .sheet(item: $editingType) { t in
            TypeFormSheet(type: t, styleId: t.styleId) { await onRefresh() }
        }
    }

    @ViewBuilder
    private func deleteTypeButton(_ typeId: Int64) -> some View {
        Button(role: .destructive) {
            deleteAction = {
                guard let service = appCore.partsService else { return }
                do {
                    try service.deleteType(id: typeId)
                    await onRefresh()
                } catch {
                    print("[EditorPanel] Delete type error: \(error)")
                }
            }
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    // MARK: - Stat Pill

    @ViewBuilder
    private func statPill(value: Int, label: String) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, DS.Space.sm)
        .padding(.horizontal, DS.Space.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
