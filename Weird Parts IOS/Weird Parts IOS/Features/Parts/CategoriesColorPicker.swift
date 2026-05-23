import SwiftUI
import WiredPartCore

/// Variant picker for a specific type — selecting a shared `part_colors` row creates a Part
/// in the catalog with the full hierarchy path (category, style, type, brand, variant).
struct CategoriesColorPicker: View {
    let typeId: Int64
    let brandId: Int64?
    let hierarchy: PartsService.HierarchyTree

    @EnvironmentObject private var appCore: AppCore
    @State private var allColors: [PartColor] = []
    @State private var linkedColorIds: Set<Int64> = []
    @State private var isLoading = true
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case addVariant
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var confirmColor: PartColor?
    @State private var showConfirmation = false
    @State private var recentlyAdded: Set<Int64> = []
    @State private var errorMessage: String?

    var onRefresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Shared variants")
                    .font(.headline)
                Spacer()
                Button {
                    activeSheet = .addVariant
                } label: {
                    Label("Add New Variant", systemImage: "plus")
                        .font(.caption)
                }
            }

            if let error = loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if allColors.isEmpty {
                Text("No variants in the shared pool. Add a variant to create catalog entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Shared part_colors pool — not scoped to this type/brand.
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 180), spacing: DS.Space.sm)
                ], spacing: DS.Space.sm) {
                    ForEach(allColors, id: \.id) { color in
                        colorTile(color)
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await loadColors() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addVariant:
                ColorFormSheet(color: nil) {
                    await loadColors()
                    await onRefresh()
                }
            }
        }
        .alert("Add to Catalog?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Add to Catalog") {
                if let color = confirmColor {
                    Task { await createCatalogPart(color: color) }
                }
            }
        } message: {
            if let color = confirmColor {
                Text("Add \(color.name) \(typeDescription) to the parts catalog?")
            }
        }
    }

    // MARK: - Color Tile

    @ViewBuilder
    private func colorTile(_ color: PartColor) -> some View {
        let colorId = color.id ?? 0
        let isLinked = linkedColorIds.contains(colorId)
        let wasJustAdded = recentlyAdded.contains(colorId)

        Button {
            if !isLinked {
                confirmColor = color
                showConfirmation = true
            }
        } label: {
            VStack(spacing: DS.Space.xs) {
                ZStack {
                    if let hex = color.hexCode, !hex.isEmpty, let c = Color(hex: hex) {
                        Circle()
                            .fill(c)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    } else {
                        namedOnlyPill(color.name)
                    }
                    if isLinked || wasJustAdded {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                Text(color.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isLinked ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLinked ? Color.accentColor.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(wasJustAdded ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isLinked)
    }

    private var namedOnlyPillForeground: Color { .secondary }

    /// Named-only variant rows have `hex_code = NULL`; render as text pills instead of color chips.
    private func namedOnlyPill(_ name: String) -> some View {
        Text(name.isEmpty ? "Named-only variant" : name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(namedOnlyPillForeground)
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: 36)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    /// Build a human-readable description of the current type path for confirmation dialogs.
    private var typeDescription: String {
        for catNode in hierarchy.categories {
            for styleNode in catNode.styles {
                for typeNode in styleNode.types {
                    if typeNode.type.id == typeId {
                        let brandName: String
                        if let bid = brandId {
                            brandName = typeNode.brands.first(where: { $0.id == bid })?.name ?? ""
                        } else {
                            brandName = "General"
                        }
                        return "\(typeNode.type.name) (\(brandName))"
                    }
                }
            }
        }
        return "Part"
    }

    /// Resolve the full hierarchy path (categoryId, styleId) for the current typeId.
    private func resolveHierarchyPath() -> (categoryId: Int64, styleId: Int64)? {
        for catNode in hierarchy.categories {
            guard let catId = catNode.category.id else { continue }
            for styleNode in catNode.styles {
                guard let styleId = styleNode.style.id else { continue }
                for typeNode in styleNode.types {
                    if typeNode.type.id == typeId {
                        return (catId, styleId)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Data Loading

    private func loadColors() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let colors = try service.listColors()

            // Find which colors are already linked to this brand+type via brandNodes
            var linked = Set<Int64>()
            let hierarchy = try service.getHierarchy()
            for catNode in hierarchy.categories {
                for styleNode in catNode.styles {
                    for typeNode in styleNode.types {
                        if typeNode.type.id == typeId {
                            // Find the matching brand node
                            let matchingBrandNode: PartsService.BrandNode?
                            if let bid = brandId {
                                matchingBrandNode = typeNode.brandNodes.first(where: { $0.brand?.id == bid })
                            } else {
                                matchingBrandNode = typeNode.brandNodes.first(where: { $0.isGeneral })
                            }
                            if let brandNode = matchingBrandNode {
                                for color in brandNode.colors {
                                    if let cid = color.id {
                                        linked.insert(cid)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            await MainActor.run {
                allColors = colors
                linkedColorIds = linked
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load colors")
                isLoading = false
            }
        }
    }

    // MARK: - Create Catalog Part

    private func createCatalogPart(color: PartColor) async {
        guard let service = appCore.partsService else {
            errorMessage = "Service not available"
            return
        }
        guard let colorId = color.id else { return }
        guard let path = resolveHierarchyPath() else {
            errorMessage = "Could not resolve hierarchy path for this type."
            return
        }

        do {
            // Link the color to the type
            try service.linkTypeToColor(typeId: typeId, colorId: colorId)

            // Build a descriptive name for the catalog part
            let typeName = typeDescription
            let partName = "\(color.name) \(typeName)"

            // Create the part in the catalog
            try service.createPart(
                categoryId: path.categoryId,
                name: partName,
                partType: brandId == nil ? "general" : "branded",
                styleId: path.styleId,
                typeId: typeId,
                colorId: colorId,
                brandId: brandId
            )

            await MainActor.run {
                linkedColorIds.insert(colorId)
                recentlyAdded.insert(colorId)
                errorMessage = nil
            }

            await onRefresh()
        } catch {
            await MainActor.run {
                errorMessage = userFriendlyError(error, context: "create catalog entry")
            }
            // errorMessage already set above for UI display
        }
    }
}
