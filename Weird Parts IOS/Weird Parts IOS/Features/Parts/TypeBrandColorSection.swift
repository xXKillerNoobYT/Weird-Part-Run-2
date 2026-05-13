import SwiftUI
import WiredPartCore

struct BrandRemovalConfirmation: Identifiable, Equatable {
    let brandId: Int64
    let brandName: String

    var id: Int64 { brandId }

    var message: String {
        "Are you sure you want to remove brand \(brandName) from this type? This may affect linked parts and colors."
    }
}

enum TypeBrandSelectionDefaults {
    static let isGeneralSelectedOnLoad = true
}

/// Flat variant-grouped SKU view for a Type.
///
/// Layout:
/// 1. "Brands" header with selectable brand chips (link/unlink brands to this type)
/// 2. "Variants & SKUs" section showing a flat list of variants (part_colors linked to this type)
///    grouped by variant — each variant row shows its chip, and underneath it the per-brand
///    SKU rows from `color_brand_skus` with brand badge + part number + cost.
/// 3. Tapping a SKU row opens an inline editor for SKU-level fields (part_number, unit_cost).
///    Editing never mutates the parent `part_colors` row.
struct TypeBrandColorSection: View {
    let typeId: Int64
    let hierarchy: PartsService.HierarchyTree
    var onRefresh: () async -> Void
    var onAddColor: () -> Void

    @EnvironmentObject private var appCore: AppCore

    // Brand data
    @State private var allBrands: [Brand] = []
    @State private var linkedBrandIds: Set<Int64> = []
    @State private var isGeneralLinked = false

    // Variant + SKU data
    @State private var linkedColors: [PartColor] = []
    @State private var skusByColor: [Int64: [PartsService.ColorBrandSKU]] = [:]

    // UI state
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var pendingBrandRemoval: BrandRemovalConfirmation?
    @State private var editingSKU: PartsService.ColorBrandSKU?
    @State private var editPartNumber: String = ""
    @State private var editUnitCost: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            // MARK: - Brand Selection
            brandSelectionSection

            Divider()

            // MARK: - Variants & SKUs
            variantSKUSection
        }
        .task { await loadAllData() }
        .confirmationDialog(
            "Remove Brand?",
            isPresented: Binding(
                get: { pendingBrandRemoval != nil },
                set: { if !$0 { pendingBrandRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingBrandRemoval
        ) { removal in
            Button("Remove", role: .destructive) {
                Task { await removeBrand(removal) }
            }
            Button("Cancel", role: .cancel) {
                pendingBrandRemoval = nil
            }
        } message: { removal in
            Text(removal.message)
        }
        .sheet(item: $editingSKU) { sku in
            SKUEditorSheet(
                sku: sku,
                brandName: brandName(for: sku.brandId),
                colorName: colorName(for: sku.colorId),
                onSave: { partNumber, unitCost in
                    Task { await saveSKU(skuId: sku.id, partNumber: partNumber, unitCost: unitCost) }
                },
                onDelete: {
                    Task { await deleteSKU(skuId: sku.id) }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Brand Selection Section

    @ViewBuilder
    private var brandSelectionSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Brands")
                    .font(.headline)
                Spacer()
            }

            if let error = loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                brandChipGrid
            }
        }
    }

    // MARK: - Brand Chip Grid

    @ViewBuilder
    private var brandChipGrid: some View {
        BrandFlowLayout(spacing: 8) {
            // General chip
            brandChip(name: "General", isSelected: isGeneralLinked) {
                isGeneralLinked.toggle()
            }

            // Named brand chips
            ForEach(allBrands, id: \.id) { brand in
                let brandId = brand.id ?? 0
                let isLinked = linkedBrandIds.contains(brandId)
                brandChip(name: brand.name, isSelected: isLinked) {
                    if isLinked {
                        pendingBrandRemoval = BrandRemovalConfirmation(brandId: brandId, brandName: brand.name)
                    } else {
                        Task { await addBrand(brandId: brandId) }
                    }
                }
            }
        }

        if allBrands.isEmpty {
            Text("No brands in the system yet. Add brands from the Brands tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, DS.Space.sm)
        }
    }

    // MARK: - Brand Chip

    @ViewBuilder
    private func brandChip(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption).bold()
                }
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Variants & SKUs Section

    @ViewBuilder
    private var variantSKUSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Variants & SKUs")
                    .font(.headline)
                Spacer()
                Button {
                    onAddColor()
                } label: {
                    Label("Add Variant", systemImage: "plus")
                        .font(.caption)
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if linkedColors.isEmpty {
                Text("No variants linked to this type yet. Add a variant to create catalog entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.sm)
            } else {
                ForEach(linkedColors, id: \.id) { color in
                    variantGroupCard(color: color)
                }
            }
        }
    }

    // MARK: - Variant Group Card

    @ViewBuilder
    private func variantGroupCard(color: PartColor) -> some View {
        let colorId = color.id ?? 0
        let skus = skusByColor[colorId] ?? []

        VStack(alignment: .leading, spacing: 0) {
            // Variant header row
            HStack(spacing: DS.Space.sm) {
                variantChip(color: color)

                if let pn = color.partNumber, !pn.isEmpty {
                    Text(pn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(skus.count) SKU\(skus.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.Space.md)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: skus.isEmpty ? 10 : 0,
                    bottomTrailingRadius: skus.isEmpty ? 10 : 0,
                    topTrailingRadius: 10
                )
                .fill(Color(.secondarySystemGroupedBackground))
            )

            // SKU rows underneath
            if !skus.isEmpty {
                VStack(spacing: 0) {
                    ForEach(skus, id: \.id) { sku in
                        skuRow(sku: sku)
                        if sku.id != skus.last?.id {
                            Divider().padding(.leading, DS.Space.lg)
                        }
                    }
                }
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 0
                    )
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.5))
                )
            }
        }
    }

    // MARK: - Variant Chip

    @ViewBuilder
    private func variantChip(color: PartColor) -> some View {
        HStack(spacing: 4) {
            if let hex = color.hexCode, !hex.isEmpty, let c = Color(hex: hex) {
                Circle()
                    .fill(c)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            }
            Text(color.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                color.hexCode != nil
                    ? Color(.secondarySystemGroupedBackground)
                    : Color.accentColor.opacity(0.1)
            )
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - SKU Row

    @ViewBuilder
    private func skuRow(sku: PartsService.ColorBrandSKU) -> some View {
        Button {
            editPartNumber = sku.partNumber ?? ""
            editUnitCost = sku.unitCost.map { String(format: "%.2f", $0) } ?? ""
            editingSKU = sku
        } label: {
            HStack(spacing: DS.Space.sm) {
                // Brand badge
                Text(brandName(for: sku.brandId))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)

                // Part number
                if let pn = sku.partNumber, !pn.isEmpty {
                    Text(pn)
                        .font(.caption)
                        .foregroundStyle(.primary)
                } else {
                    Text("No part #")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Unit cost
                if let cost = sku.unitCost {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func brandName(for brandId: Int64) -> String {
        allBrands.first(where: { $0.id == brandId })?.name ?? "Unknown"
    }

    private func colorName(for colorId: Int64) -> String {
        linkedColors.first(where: { $0.id == colorId })?.name ?? "Unknown"
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let brands = try service.listBrands()
            let allBrandsList = brands.map(\.brand)

            // Find linked brand IDs from hierarchy
            let hierarchy = try service.getHierarchy()
            var linkedIds = Set<Int64>()
            var colors: [PartColor] = []

            for catNode in hierarchy.categories {
                for styleNode in catNode.styles {
                    for typeNode in styleNode.types {
                        if typeNode.type.id == typeId {
                            for brand in typeNode.brands {
                                if let bid = brand.id {
                                    linkedIds.insert(bid)
                                }
                            }
                            // Collect all linked colors (deduplicated)
                            var seenColorIds = Set<Int64>()
                            for color in typeNode.colors {
                                if let cid = color.id, seenColorIds.insert(cid).inserted {
                                    colors.append(color)
                                }
                            }
                        }
                    }
                }
            }

            // Load SKUs for this type
            let allSKUs = try service.getSKUsForType(typeId: typeId)
            var grouped: [Int64: [PartsService.ColorBrandSKU]] = [:]
            for sku in allSKUs {
                grouped[sku.colorId, default: []].append(sku)
            }

            await MainActor.run {
                allBrands = allBrandsList
                linkedBrandIds = linkedIds
                isGeneralLinked = TypeBrandSelectionDefaults.isGeneralSelectedOnLoad
                linkedColors = colors
                skusByColor = grouped
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load type data")
                isLoading = false
            }
        }
    }

    // MARK: - Brand Actions

    private func addBrand(brandId: Int64) async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.linkTypeToBrand(typeId: typeId, brandId: brandId)

            // Auto-create SKU rows for all linked colors with this new brand
            for color in linkedColors {
                guard let colorId = color.id else { continue }
                try service.upsertColorBrandSKU(colorId: colorId, brandId: brandId, typeId: typeId)
            }

            await MainActor.run {
                linkedBrandIds.insert(brandId)
            }
            await reloadSKUs()
            await onRefresh()
        } catch {
            loadError = userFriendlyError(error, context: "link brand")
        }
    }

    private func removeBrand(_ removal: BrandRemovalConfirmation) async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            let linkId = try service.getTypeBrandLinkId(typeId: typeId, brandId: removal.brandId)
            if let linkId {
                try service.unlinkTypeBrand(linkId: linkId)
            }
            await MainActor.run {
                linkedBrandIds.remove(removal.brandId)
                pendingBrandRemoval = nil
            }
            await reloadSKUs()
            await onRefresh()
        } catch {
            loadError = userFriendlyError(error, context: "remove brand")
        }
    }

    // MARK: - SKU Actions

    private func saveSKU(skuId: Int64, partNumber: String?, unitCost: Double?) async {
        guard let service = appCore.partsService else { return }
        do {
            try service.updateColorBrandSKU(skuId: skuId, partNumber: partNumber, unitCost: unitCost)
            await MainActor.run { editingSKU = nil }
            await reloadSKUs()
        } catch {
            loadError = userFriendlyError(error, context: "save SKU")
        }
    }

    private func deleteSKU(skuId: Int64) async {
        guard let service = appCore.partsService else { return }
        do {
            try service.deleteColorBrandSKU(skuId: skuId)
            await MainActor.run { editingSKU = nil }
            await reloadSKUs()
        } catch {
            loadError = userFriendlyError(error, context: "delete SKU")
        }
    }

    private func reloadSKUs() async {
        guard let service = appCore.partsService else { return }
        do {
            let allSKUs = try service.getSKUsForType(typeId: typeId)
            var grouped: [Int64: [PartsService.ColorBrandSKU]] = [:]
            for sku in allSKUs {
                grouped[sku.colorId, default: []].append(sku)
            }
            await MainActor.run {
                skusByColor = grouped
            }
        } catch {
            // Silently fail reload — data will refresh on next full load
        }
    }
}

// MARK: - SKU Editor Sheet

private struct SKUEditorSheet: View {
    let sku: PartsService.ColorBrandSKU
    let brandName: String
    let colorName: String
    let onSave: (String?, Double?) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var partNumber: String = ""
    @State private var unitCost: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Variant")
                        Spacer()
                        Text(colorName).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Brand")
                        Spacer()
                        Text(brandName).foregroundStyle(.secondary)
                    }
                }

                Section("SKU Details") {
                    TextField("Part Number", text: $partNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Unit Cost", text: $unitCost)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button("Delete SKU", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit SKU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let pn = partNumber.trimmingCharacters(in: .whitespaces)
                        let cost = Double(unitCost)
                        onSave(pn.isEmpty ? nil : pn, cost)
                        dismiss()
                    }
                }
            }
            .onAppear {
                partNumber = sku.partNumber ?? ""
                unitCost = sku.unitCost.map { String(format: "%.2f", $0) } ?? ""
            }
        }
    }
}

// MARK: - Identifiable conformance for ColorBrandSKU

extension PartsService.ColorBrandSKU: @retroactive Identifiable {}

// MARK: - BrandFlowLayout (wrapping horizontal layout)

/// A simple flow layout that wraps children to the next line when they don't fit.
struct BrandFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: width, height: y + rowHeight)
        )
    }

    struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }
}
