import SwiftUI
import WiredPartCore

/// Left-panel editor that shows the appropriate editing UI
/// based on which node is selected in the tree.
struct CategoriesEditorPanel: View {
    let selection: TreeSelection?
    let hierarchy: PartsService.HierarchyTree
    var onRefresh: () async -> Void

    @EnvironmentObject private var appCore: AppCore

    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addStyle(Int64)
        case addType(Int64)
        case addColor
        case editCategory(PartCategory)
        case editStyle(PartStyle)
        case editType(PartType)
        case editColor(PartColor)
        case smartDelete(entityType: String, entityId: Int64, entityName: String)

        var id: String {
            switch self {
            case .addStyle(let id): return "addStyle-\(id)"
            case .addType(let id): return "addType-\(id)"
            case .addColor: return "addColor"
            case .editCategory(let c): return "editCat-\(c.id ?? 0)"
            case .editStyle(let s): return "editStyle-\(s.id ?? 0)"
            case .editType(let t): return "editType-\(t.id ?? 0)"
            case .editColor(let c): return "editColor-\(c.id ?? 0)"
            case .smartDelete(let type, let id, _): return "smartDelete-\(type)-\(id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

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
        .sheet(item: $activeSheet, onDismiss: {
            // Safety net: always refresh when any sheet closes
            Task { await onRefresh() }
        }) { sheet in
            switch sheet {
            case .addStyle(let catId):
                StyleFormSheet(style: nil, categoryId: catId) { await onRefresh() }
            case .addType(let styleId):
                TypeFormSheet(type: nil, styleId: styleId) { await onRefresh() }
            case .addColor:
                ColorFormSheet(color: nil) { await onRefresh() }
            case .editCategory(let cat):
                CategoryFormSheet(category: cat) { await onRefresh() }
            case .editStyle(let s):
                StyleFormSheet(style: s, categoryId: s.categoryId) { await onRefresh() }
            case .editType(let t):
                TypeFormSheet(type: t, styleId: t.styleId) { await onRefresh() }
            case .editColor(let c):
                ColorFormSheet(color: c) { await onRefresh() }
            case .smartDelete(let type, let id, let name):
                SmartDeleteSheet(entityType: type, entityId: id, entityName: name) {
                    await onRefresh()
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptySelection: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Image(systemName: "sidebar.squares.left")
                .decorativeIconFont(48)
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
        case .sku(let skuId, let colorId, let typeId, let brandId):
            skuEditor(skuId: skuId, colorId: colorId, typeId: typeId, brandId: brandId)
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
                    deleteCategoryButton(catId, name: catNode.category.name)
                }

                Divider()

                // Sub-items: Styles in this category
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text("Styles")
                            .font(.headline)
                        Spacer()
                        Button {
                            activeSheet = .addStyle(catId)
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
                    deleteStyleButton(styleId, name: styleNode.style.name)
                }

                Divider()

                // Sub-items: Types in this style
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text("Types")
                            .font(.headline)
                        Spacer()
                        Button {
                            activeSheet = .addType(styleId)
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
                    statPill(value: typeNode.colors.count, label: "Variants")
                }

                Divider()

                HStack(spacing: DS.Space.md) {
                    editTypeButton(typeNode.type)
                    deleteTypeButton(typeId, name: typeNode.type.name)
                }

                Divider()

                // Brand selection + per-brand color pickers
                TypeBrandColorSection(
                    typeId: typeId,
                    hierarchy: hierarchy,
                    onRefresh: onRefresh,
                    onAddColor: { activeSheet = .addColor }
                )
            }
        } else {
            Text("Type not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Brand Editor

    @ViewBuilder
    private func brandEditor(brandId: Int64, typeId: Int64) -> some View {
        if brandId == 0 {
            typeEditor(typeId: typeId)
        } else if let (_, _, typeNode) = findType(typeId) {
            let brandNode = typeNode.brandNodes.first(where: { $0.id == brandId })
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Label("Brand", systemImage: "tag.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(brandNode?.name ?? "Brand")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: DS.Space.xs) {
                    Text("on type")
                        .foregroundStyle(.secondary)
                    Text(typeNode.type.name)
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                Divider()

                if let brandNode {
                    statPill(value: brandNode.colors.count, label: "Variants")

                    Divider()
                }

                // Brand section focused on this specific brand
                CategoriesBrandSection(typeId: typeId, focusedBrandId: brandId == 0 ? nil : brandId)

                Divider()

                // Variant picker for this brand — prominent section
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Label("Available Variants", systemImage: "paintpalette.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Pick a variant below to create a catalog entry for this brand + type + variant combination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CategoriesColorPicker(
                        typeId: typeId,
                        brandId: brandId == 0 ? nil : brandId,
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

    // MARK: - SKU Editor

    @ViewBuilder
    private func skuEditor(skuId: Int64, colorId: Int64, typeId: Int64, brandId: Int64) -> some View {
        let color = findColor(colorId)
        let brand = try? appCore.partsService?.getBrand(id: brandId)
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Label("Brand SKU", systemImage: "number.square.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(color?.name ?? "Variant")
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: DS.Space.xs) {
                    Text(brand?.name ?? "Brand")
                        .fontWeight(.medium)
                    Text("on")
                        .foregroundStyle(.secondary)
                    if let (_, _, typeNode) = findType(typeId) {
                        Text(typeNode.type.name)
                            .fontWeight(.medium)
                    }
                }
                .font(.subheadline)
            }

            Text("This edits the SKU for this exact variant + brand + type. The reusable variant remains shared across the catalog.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ColorBrandSKUEditorPanel(skuId: skuId, onRefresh: onRefresh)
        }
    }

    // MARK: - Variant Editor

    @ViewBuilder
    private func colorEditor(colorId: Int64, typeId: Int64, brandId: Int64?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Label("Variant", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Find the color in the hierarchy
            if let color = findColor(colorId) {
                HStack(spacing: DS.Space.md) {
                    colorSwatch(hex: color.hexCode)
                    VStack(alignment: .leading) {
                        Text(color.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        if let hex = color.hexCode {
                            Text(hex)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        } else {
                            Text("No color value")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Internal Part Number
                if let pn = color.partNumber, !pn.isEmpty {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("PN: \(pn)")
                            .font(.subheadline)
                            .monospaced()
                    }
                } else {
                    Text("No part number assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                // Show parent context
                if let (_, _, typeNode) = findType(typeId) {
                    HStack(spacing: DS.Space.xs) {
                        Text("on type")
                            .foregroundStyle(.secondary)
                        Text(typeNode.type.name)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }

                Divider()

                // Stats
                HStack(spacing: DS.Space.xl) {
                    statPill(value: color.sortOrder, label: "Sort Order")
                    if color.hexCode != nil {
                        statPill(value: 1, label: "Has Color")
                    } else {
                        statPill(value: 0, label: "No Color")
                    }
                }

                Divider()

                // Action buttons
                HStack(spacing: DS.Space.md) {
                    editColorButton(color)
                    deleteColorButton(colorId, name: color.name)
                }

                Divider()

                // Supplier Part Numbers section
                ColorSupplierPartNumbersSection(colorId: colorId)

                Divider()

                Text("This color is linked to the type. Parts with this color combination appear in the catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Variant not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Color swatch circle, handles nil hex gracefully
    @ViewBuilder
    private func colorSwatch(hex: String?) -> some View {
        if let hex, !hex.isEmpty, let resolved = Color(hex: hex) {
            Circle()
                .fill(resolved)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        } else {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                Image(systemName: "nosign")
                    .font(.caption)
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

    @ViewBuilder
    private func editCategoryButton(_ category: PartCategory) -> some View {
        Button {
            activeSheet = .editCategory(category)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("editCategoryButton")
    }

    @ViewBuilder
    private func deleteCategoryButton(_ catId: Int64, name: String) -> some View {
        Button(role: .destructive) {
            activeSheet = .smartDelete(entityType: "category", entityId: catId, entityName: name)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("deleteCategoryButton")
    }

    @ViewBuilder
    private func editStyleButton(_ style: PartStyle) -> some View {
        Button {
            activeSheet = .editStyle(style)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("editStyleButton")
    }

    @ViewBuilder
    private func deleteStyleButton(_ styleId: Int64, name: String) -> some View {
        Button(role: .destructive) {
            activeSheet = .smartDelete(entityType: "style", entityId: styleId, entityName: name)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("deleteStyleButton")
    }

    @ViewBuilder
    private func editTypeButton(_ ptype: PartType) -> some View {
        Button {
            activeSheet = .editType(ptype)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("editTypeButton")
    }

    @ViewBuilder
    private func deleteTypeButton(_ typeId: Int64, name: String) -> some View {
        Button(role: .destructive) {
            activeSheet = .smartDelete(entityType: "type", entityId: typeId, entityName: name)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("deleteTypeButton")
    }

    @ViewBuilder
    private func editColorButton(_ color: PartColor) -> some View {
        Button {
            activeSheet = .editColor(color)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("editColorButton")
    }

    @ViewBuilder
    private func deleteColorButton(_ colorId: Int64, name: String) -> some View {
        Button(role: .destructive) {
            activeSheet = .smartDelete(entityType: "color", entityId: colorId, entityName: name)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityIdentifier("deleteColorButton")
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

// MARK: - Color Supplier Part Numbers Section

/// Shows supplier-specific part numbers for a color, collapsed by default.
struct ColorSupplierPartNumbersSection: View {
    let colorId: Int64
    @EnvironmentObject private var appCore: AppCore
    @State private var supplierParts: [(supplierId: Int64, supplierName: String, supplierPartNumber: String?)] = []
    @State private var isExpanded = false
    @State private var isLoading = false

    var body: some View {
        DisclosureGroup("Supplier Part Numbers", isExpanded: $isExpanded) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Space.sm)
            } else if supplierParts.isEmpty {
                Text("No suppliers linked to parts with this color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.sm)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(supplierParts, id: \.supplierId) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.supplierName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let spn = entry.supplierPartNumber, !spn.isEmpty {
                                    Text(spn)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No supplier PN")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, DS.Space.xxs)
                    }
                }
            }
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .onChange(of: isExpanded) {
            if isExpanded && supplierParts.isEmpty {
                loadSupplierParts()
            }
        }
    }

    private func loadSupplierParts() {
        guard let service = appCore.partsService else { return }
        isLoading = true
        Task.detached {
            let results: [(supplierId: Int64, supplierName: String, supplierPartNumber: String?)]
            do {
                results = try service.getColorSupplierPartNumbers(colorId: colorId)
            } catch {
                results = [] // Non-critical: supplier part numbers may not be configured
            }
            await MainActor.run {
                supplierParts = results
                isLoading = false
            }
        }
    }
}

// MARK: - Color Brand SKU Editor Panel

struct ColorBrandSKUEditorPanel: View {
    let skuId: Int64
    var onRefresh: () async -> Void

    @EnvironmentObject private var appCore: AppCore
    @State private var sku: PartsService.ColorBrandSKU?
    @State private var partNumber = ""
    @State private var unitCost = ""
    @State private var stockQty = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Space.md)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Part Number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Manufacturer SKU", text: $partNumber)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Unit Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $unitCost)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Stock Quantity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: $stockQty)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save SKU", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .task(id: skuId) {
            load()
        }
    }

    private func load() {
        guard let service = appCore.partsService else {
            isLoading = false
            errorMessage = "Parts service not available."
            return
        }

        do {
            let loaded = try service.getColorBrandSKU(skuId: skuId)
            sku = loaded
            partNumber = loaded?.partNumber ?? ""
            unitCost = loaded?.unitCost.map { String(format: "%.2f", $0) } ?? ""
            stockQty = loaded.map { String($0.stockQty) } ?? "0"
            errorMessage = loaded == nil ? "SKU row not found." : nil
            isLoading = false
        } catch {
            errorMessage = userFriendlyError(error, context: "load SKU")
            isLoading = false
        }
    }

    private func save() {
        guard let service = appCore.partsService else {
            errorMessage = "Parts service not available."
            return
        }

        let trimmedPartNumber = partNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPartNumber = trimmedPartNumber.isEmpty ? "" : trimmedPartNumber
        let normalizedUnitCost: Double?
        if unitCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedUnitCost = nil
        } else if let parsed = Double(unitCost) {
            normalizedUnitCost = parsed
        } else {
            errorMessage = "Unit cost must be a number."
            return
        }

        let normalizedStockQty: Int?
        if stockQty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedStockQty = 0
        } else if let parsed = Int(stockQty), parsed >= 0 {
            normalizedStockQty = parsed
        } else {
            errorMessage = "Stock quantity must be a whole number."
            return
        }

        isSaving = true
        Task {
            do {
                try service.updateColorBrandSKU(
                    skuId: skuId,
                    partNumber: normalizedPartNumber,
                    unitCost: normalizedUnitCost,
                    stockQty: normalizedStockQty
                )
                let refreshed = try service.getColorBrandSKU(skuId: skuId)
                sku = refreshed
                errorMessage = nil
                isSaving = false
                await onRefresh()
            } catch {
                errorMessage = userFriendlyError(error, context: "save SKU")
                isSaving = false
            }
        }
    }
}
