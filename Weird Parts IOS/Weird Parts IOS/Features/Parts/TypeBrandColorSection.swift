import SwiftUI
import WiredPartCore

/// Combined brand selection + per-brand color picker for a Type.
///
/// Layout:
/// 1. "Brands" header with all available brands as tappable chips
/// 2. Selected brands shown in a highlighted row
/// 3. Under each selected brand, a color picker to assign colors
///    (since not all brands carry the same colors)
struct TypeBrandColorSection: View {
    let typeId: Int64
    let hierarchy: PartsService.HierarchyTree
    var onRefresh: () async -> Void
    var onAddColor: () -> Void

    @EnvironmentObject private var appCore: AppCore

    @State private var allBrands: [Brand] = []
    @State private var linkedBrandIds: Set<Int64> = []
    @State private var isGeneralLinked = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var expandedBrandId: Int64? // Which brand's color picker is open
    @State private var mfrPartNumbers: [Int64: String] = [:]

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
                // All brands as selectable chips
                brandChipGrid

                // Selected brands with per-brand color pickers
                if !selectedBrands.isEmpty || isGeneralLinked {
                    Divider()

                    Text("Selected Brands")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    // General brand card (if linked)
                    if isGeneralLinked {
                        selectedBrandCard(name: "General", brandId: nil)
                    }

                    // Named brand cards
                    ForEach(selectedBrands, id: \.id) { brand in
                        selectedBrandCard(name: brand.name, brandId: brand.id)
                    }
                }

                Divider()

                // Add color shortcut
                Button {
                    onAddColor()
                } label: {
                    Label("Create New Color", systemImage: "paintpalette")
                }
                .buttonStyle(.bordered)
            }
        }
        .task { await loadBrandData() }
    }

    // MARK: - Selected brands helper

    private var selectedBrands: [Brand] {
        allBrands.filter { linkedBrandIds.contains($0.id ?? 0) }
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
                        .font(.system(size: 10, weight: .bold))
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

    // MARK: - Selected Brand Card (with color picker underneath)

    @ViewBuilder
    private func selectedBrandCard(name: String, brandId: Int64?) -> some View {
        let isExpanded = expandedBrandId == (brandId ?? -1)

        VStack(alignment: .leading, spacing: 0) {
            // Brand header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedBrandId = nil
                    } else {
                        expandedBrandId = brandId ?? -1
                    }
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Mfr part number warning (named brands only)
                    if let bid = brandId {
                        let mfrPn = mfrPartNumbers[bid] ?? ""
                        if mfrPn.trimmingCharacters(in: .whitespaces).isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: isExpanded ? 0 : 10)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: isExpanded ? 0 : 10,
                        bottomTrailingRadius: isExpanded ? 0 : 10,
                        topTrailingRadius: 10
                    )
                )
            }
            .buttonStyle(.plain)

            // Expanded: Mfr part number + Color picker
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    // Manufacturer part number (named brands only)
                    if let bid = brandId {
                        HStack(spacing: DS.Space.sm) {
                            Text("Mfr Part #:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Manufacturer part number", text: Binding(
                                get: { mfrPartNumbers[bid] ?? "" },
                                set: { mfrPartNumbers[bid] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        }
                    } else {
                        Text("General — no specific brand, no part number needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Color picker for this brand
                    CategoriesColorPicker(
                        typeId: typeId,
                        brandId: brandId,
                        hierarchy: hierarchy,
                        onRefresh: onRefresh
                    )
                }
                .padding(DS.Space.md)
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

    // MARK: - Data Loading

    private func loadBrandData() async {
        guard let service = appCore.partsService else { isLoading = false; return }
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

            await MainActor.run {
                allBrands = allBrandsList
                linkedBrandIds = linkedIds
                isLoading = false
                // Auto-expand first selected brand
                if let first = allBrandsList.first(where: { linkedIds.contains($0.id ?? 0) }) {
                    expandedBrandId = first.id
                } else if isGeneralLinked {
                    expandedBrandId = -1
                }
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Toggle Brand Link

    private func toggleBrand(brandId: Int64, isLinked: Bool) async {
        guard let service = appCore.partsService else { return }
        do {
            if isLinked {
                let linkId = try service.getTypeBrandLinkId(typeId: typeId, brandId: brandId)
                if let linkId {
                    try service.unlinkTypeBrand(linkId: linkId)
                }
                await MainActor.run {
                    linkedBrandIds.remove(brandId)
                    if expandedBrandId == brandId {
                        expandedBrandId = nil
                    }
                }
            } else {
                try service.linkTypeToBrand(typeId: typeId, brandId: brandId)
                await MainActor.run {
                    linkedBrandIds.insert(brandId)
                    expandedBrandId = brandId // Auto-expand newly linked brand
                }
            }
            await onRefresh()
        } catch {
            loadError = "Toggle failed: \(error.localizedDescription)"
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
