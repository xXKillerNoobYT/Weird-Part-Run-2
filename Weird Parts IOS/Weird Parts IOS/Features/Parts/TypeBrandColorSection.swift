import SwiftUI
import WiredPartCore

/// Flat variant + SKU section for a Type.
///
/// Layout:
/// 1. "Brands" header with all available brands as tappable chips (link/unlink)
/// 2. "Variants & SKUs" — flat list of SKU rows from `color_brand_skus`,
///    grouped by shared Variant (PartColor). Brand data appears only on SKU rows,
///    never on the Variant chip itself.
/// 3. Tapping a SKU row opens the SKU editor; editing never mutates the parent `part_colors` row.
struct TypeBrandColorSection: View {
    let typeId: Int64
    let hierarchy: PartsService.HierarchyTree
    var onRefresh: () async -> Void
    var onAddColor: () -> Void

    @EnvironmentObject private var appCore: AppCore

    @State private var allBrands: [Brand] = []
    @State private var linkedBrandIds: Set<Int64> = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var skus: [PartsService.ColorBrandSKU] = []
    @State private var colorById: [Int64: PartColor] = [:]
    @State private var brandById: [Int64: Brand] = [:]
    @State private var editingSKUId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // MARK: - Brand Selection
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

                Divider()

                // MARK: - Variants & SKUs
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

                if skuGroups.isEmpty {
                    emptyVariantsView
                } else {
                    variantGroupedList
                }
            }
        }
        .task { await loadData() }
        .sheet(item: $editingSKUId) { skuId in
            NavigationStack {
                ColorBrandSKUEditorPanel(skuId: skuId, onRefresh: {
                    await loadSKUs()
                    await onRefresh()
                })
            }
        }
    }

    // MARK: - SKU groups keyed by colorId

    private typealias VariantGroup = (variant: PartColor, skus: [PartsService.ColorBrandSKU])

    private var skuGroups: [VariantGroup] {
        let grouped = Dictionary(grouping: skus, by: \.colorId)
        return grouped
            .compactMap { (colorId, skuList) -> VariantGroup? in
                guard let variant = colorById[colorId] else { return nil }
                return (variant: variant, skus: skuList)
            }
            .sorted { ($0.variant.name) < ($1.variant.name) }
    }

    // MARK: - Variant Grouped List

    @ViewBuilder
    private var variantGroupedList: some View {
        ForEach(skuGroups, id: \.variant.id) { group in
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                // Variant chip header — no brand info here
                variantChip(for: group.variant)

                // SKU rows for this variant
                ForEach(group.skus, id: \.id) { sku in
                    skuRow(sku)
                }
            }
            .padding(DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Variant Chip (color or named-only)

    @ViewBuilder
    private func variantChip(for color: PartColor) -> some View {
        HStack(spacing: 6) {
            if let hex = color.hexCode, !hex.isEmpty {
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 14, height: 14)
            }
            Text(color.name)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(chipBackground(for: color))
        )
    }

    private func chipBackground(for color: PartColor) -> Color {
        if let hex = color.hexCode, !hex.isEmpty {
            return (Color(hex: hex) ?? .gray).opacity(0.15)
        }
        return Color(.tertiarySystemGroupedBackground)
    }

    // MARK: - SKU Row

    @ViewBuilder
    private func skuRow(_ sku: PartsService.ColorBrandSKU) -> some View {
        Button {
            editingSKUId = sku.id
        } label: {
            HStack(spacing: DS.Space.sm) {
                // Brand badge
                let brandName = brandById[sku.brandId]?.name ?? "Brand #\(sku.brandId)"
                Text(brandName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)

                // Part number
                if let pn = sku.partNumber, !pn.isEmpty {
                    Text(pn)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Text("No part #")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Unit cost if set
                if let cost = sku.unitCost {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, DS.Space.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyVariantsView: some View {
        VStack(spacing: DS.Space.sm) {
            if linkedBrandIds.isEmpty {
                Text("Link brands above, then add variants to create SKU rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No SKU rows yet. Add variants and assign them to linked brands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.md)
    }

    // MARK: - Brand Chip Grid

    @ViewBuilder
    private var brandChipGrid: some View {
        BrandFlowLayout(spacing: 8) {
            ForEach(allBrands, id: \.id) { brand in
                let brandId = brand.id ?? 0
                let isLinked = linkedBrandIds.contains(brandId)
                brandChip(name: brand.name, isSelected: isLinked) {
                    Task { await toggleBrand(brandId: brandId, isLinked: isLinked) }
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

    // MARK: - Data Loading

    private func loadData() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let brands = try service.listBrands()
            let allBrandsList = brands.map(\.brand)

            let hierarchy = try service.getHierarchy()
            var linkedIds = Set<Int64>()

            for catNode in hierarchy.categories {
                for styleNode in catNode.styles {
                    for typeNode in styleNode.types {
                        if typeNode.type.id == typeId {
                            for brand in typeNode.brands {
                                if let bid = brand.id {
                                    linkedIds.insert(bid)
                                }
                            }
                        }
                    }
                }
            }

            // Build lookup maps
            var cById: [Int64: PartColor] = [:]
            for catNode in hierarchy.categories {
                for styleNode in catNode.styles {
                    for typeNode in styleNode.types {
                        for color in typeNode.colors {
                            if let cid = color.id {
                                cById[cid] = color
                            }
                        }
                    }
                }
            }

            var bById: [Int64: Brand] = [:]
            for b in allBrandsList {
                if let bid = b.id { bById[bid] = b }
            }

            let typeSKUs = try service.getSKUsForType(typeId: typeId)

            await MainActor.run {
                allBrands = allBrandsList
                linkedBrandIds = linkedIds
                colorById = cById
                brandById = bById
                skus = typeSKUs
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load type brands")
                isLoading = false
            }
        }
    }

    private func loadSKUs() async {
        guard let service = appCore.partsService else { return }
        do {
            let typeSKUs = try service.getSKUsForType(typeId: typeId)
            await MainActor.run { skus = typeSKUs }
        } catch {
            // Non-fatal — keep existing state
        }
    }

    // MARK: - Toggle Brand Link

    private func toggleBrand(brandId: Int64, isLinked: Bool) async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            if isLinked {
                let linkId = try service.getTypeBrandLinkId(typeId: typeId, brandId: brandId)
                if let linkId {
                    try service.unlinkTypeBrand(linkId: linkId)
                }
                await MainActor.run {
                    _ = linkedBrandIds.remove(brandId)
                }
            } else {
                try service.linkTypeToBrand(typeId: typeId, brandId: brandId)
                await MainActor.run {
                    _ = linkedBrandIds.insert(brandId)
                }
            }
            await onRefresh()
        } catch {
            loadError = userFriendlyError(error, context: "toggle brand")
        }
    }
}

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
