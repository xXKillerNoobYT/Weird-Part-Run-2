import Foundation
import SwiftUI
import WiredPartCore

/// SKU-first editor for a Type's brand + variant catalog rows.
///
/// PE-COLORS Phase 2C replaces the old nested brand -> color picker mental model with
/// flat `color_brand_skus` rows grouped by variant. Each row shows:
/// - variant chip (color swatch when `hex_code` exists, text-only pill otherwise)
/// - brand badge
/// - SKU `part_number`
///
/// Tapping a row opens `ColorBrandSKUEditorSheet` for inline create/edit.
struct TypeBrandColorSection: View {
    let typeId: Int64
    let hierarchy: PartsService.HierarchyTree
    @Binding var isGeneralLinked: Bool
    var onRefresh: () async -> Void
    var onAddColor: () -> Void

    @EnvironmentObject private var appCore: AppCore

    @State private var allBrands: [Brand] = []
    @State private var allColors: [PartColor] = []
    @State private var skuRows: [ColorBrandSKUDisplayRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var pendingDelete: ColorBrandSKUDisplayRow?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(ColorBrandSKUDisplayRow)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let row): return "edit-\(row.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header

            if let error = loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                generalModeNote

                if groupedRows.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        ForEach(groupedRows) { group in
                            skuGroup(group)
                        }
                    }
                }

                Divider()

                HStack(spacing: DS.Space.sm) {
                    Button {
                        activeSheet = .create
                    } label: {
                        Label("Add SKU Row", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(allBrands.isEmpty || allColors.isEmpty)

                    Button {
                        onAddColor()
                    } label: {
                        Label("Create New Variant", systemImage: "paintpalette")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .task { await loadSKUData() }
        .sheet(item: $activeSheet, onDismiss: {
            Task { await loadSKUData(); await onRefresh() }
        }) { sheet in
            switch sheet {
            case .create:
                ColorBrandSKUEditorSheet(
                    mode: .create,
                    typeId: typeId,
                    brands: allBrands,
                    colors: allColors,
                    onSave: handleSKUSave
                )
            case .edit(let row):
                ColorBrandSKUEditorSheet(
                    mode: .edit(row),
                    typeId: typeId,
                    brands: allBrands,
                    colors: allColors,
                    onSave: handleSKUSave
                )
            }
        }
        .alert("Delete SKU Row?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { row in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task { await deleteSKU(row) }
            }
        } message: { row in
            Text("Delete the SKU row for \(row.brand.name) / \(row.color.name)? The type, brand, and variant records stay intact.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SKU Rows")
                    .font(.headline)
                Text("One row per variant + brand. Grouped by variant so part numbers are visible without opening nested pickers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !skuRows.isEmpty {
                Text("\(skuRows.count) SKU\(skuRows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }

    private var generalModeNote: some View {
        Toggle(isOn: $isGeneralLinked) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow General ordering mode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("General is not a brand SKU row; it means orders may choose a supplier first and resolve the brand later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(DS.Space.sm)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("No SKU rows yet", systemImage: "shippingbox")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(emptyStateMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyStateMessage: String {
        if allBrands.isEmpty { return "Add brands from the Brands tab before creating brand-specific SKU rows." }
        if allColors.isEmpty { return "Create at least one variant/color before creating SKU rows." }
        return "Use Add SKU Row to connect a variant, a brand, and that brand's manufacturer part number."
    }

    private var groupedRows: [ColorBrandSKUGroup] {
        let groups = Dictionary(grouping: skuRows, by: { $0.color.id ?? 0 })
        return groups.compactMap { _, rows in
            guard let first = rows.first else { return nil }
            return ColorBrandSKUGroup(color: first.color, rows: rows.sorted { $0.brand.name.localizedCaseInsensitiveCompare($1.brand.name) == .orderedAscending })
        }
        .sorted { $0.color.name.localizedCaseInsensitiveCompare($1.color.name) == .orderedAscending }
    }

    @ViewBuilder
    private func skuGroup(_ group: ColorBrandSKUGroup) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                variantChip(group.color)
                Text("\(group.rows.count) brand\(group.rows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, DS.Space.xs)

            ForEach(group.rows) { row in
                skuRow(row)
            }
        }
        .padding(DS.Space.sm)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func skuRow(_ row: ColorBrandSKUDisplayRow) -> some View {
        Button {
            activeSheet = .edit(row)
        } label: {
            HStack(spacing: DS.Space.sm) {
                variantChip(row.color)
                brandBadge(row.brand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.partNumberDisplay)
                        .font(.subheadline)
                        .fontWeight(row.sku.partNumber?.isEmpty == false ? .semibold : .regular)
                        .foregroundStyle(row.sku.partNumber?.isEmpty == false ? .primary : .secondary)
                    if let unitCost = row.sku.unitCost {
                        Text(unitCost, format: .currency(code: "USD"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.sm)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = row
            } label: {
                Label("Delete SKU Row", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func variantChip(_ color: PartColor) -> some View {
        HStack(spacing: 6) {
            if let hex = color.hexCode, !hex.isEmpty, let chipColor = Color(hex: hex) {
                Circle()
                    .fill(chipColor)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(color.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.10))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func brandBadge(_ brand: Brand) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.caption2)
            Text(brand.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12))
        .foregroundStyle(.orange)
        .clipShape(Capsule())
    }

    // MARK: - Data Loading

    private func loadSKUData() async {
        guard let service = appCore.partsService else {
            await MainActor.run {
                loadError = "Parts service not available"
                isLoading = false
            }
            return
        }

        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        do {
            let brands = try service.listBrands().map(\.brand)
            let colors = try service.listColors()
            var rows: [ColorBrandSKUDisplayRow] = []

            for brand in brands {
                guard let brandId = brand.id else { continue }
                let skus = try service.getColorBrandSKUs(typeId: typeId, brandId: brandId)
                for sku in skus {
                    guard let color = colors.first(where: { $0.id == sku.colorId }) else { continue }
                    rows.append(ColorBrandSKUDisplayRow(sku: sku, color: color, brand: brand))
                }
            }

            await MainActor.run {
                allBrands = brands
                allColors = colors
                skuRows = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load SKU rows")
                isLoading = false
            }
        }
    }

    @MainActor
    private func handleSKUSave(_ draft: ColorBrandSKUEditorSheet.Draft) async throws {
        guard let service = appCore.partsService else {
            throw NSError(domain: "TypeBrandColorSection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }

        try service.linkTypeToBrand(typeId: typeId, brandId: draft.brandId)
        try service.linkTypeToColor(typeId: typeId, colorId: draft.colorId)

        let skuId = try service.upsertColorBrandSKU(
            colorId: draft.colorId,
            brandId: draft.brandId,
            typeId: typeId,
            partNumber: draft.normalizedPartNumber,
            unitCost: draft.normalizedUnitCost
        )

        if let original = draft.originalSKU, original.id != skuId,
           (original.colorId != draft.colorId || original.brandId != draft.brandId) {
            try service.deleteColorBrandSKU(skuId: original.id)
        }

        await loadSKUData()
        await onRefresh()
    }

    private func deleteSKU(_ row: ColorBrandSKUDisplayRow) async {
        guard let service = appCore.partsService else {
            await MainActor.run { loadError = "Parts service not available" }
            return
        }
        do {
            try service.deleteColorBrandSKU(skuId: row.sku.id)
            await loadSKUData()
            await onRefresh()
        } catch {
            await MainActor.run { loadError = userFriendlyError(error, context: "delete SKU row") }
        }
    }
}

private struct ColorBrandSKUDisplayRow: Identifiable, Equatable {
    let sku: PartsService.ColorBrandSKU
    let color: PartColor
    let brand: Brand

    var id: Int64 { sku.id }

    var partNumberDisplay: String {
        let value = sku.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "No SKU part number" : value
    }

    static func == (lhs: ColorBrandSKUDisplayRow, rhs: ColorBrandSKUDisplayRow) -> Bool {
        lhs.id == rhs.id && lhs.sku.colorId == rhs.sku.colorId && lhs.sku.brandId == rhs.sku.brandId
    }
}

private struct ColorBrandSKUGroup: Identifiable {
    let color: PartColor
    let rows: [ColorBrandSKUDisplayRow]
    var id: Int64 { color.id ?? 0 }
}

private struct ColorBrandSKUEditorSheet: View {
    enum Mode {
        case create
        case edit(ColorBrandSKUDisplayRow)
    }

    struct Draft {
        let originalSKU: PartsService.ColorBrandSKU?
        let colorId: Int64
        let brandId: Int64
        let partNumber: String
        let unitCostText: String

        var normalizedPartNumber: String? {
            let trimmed = partNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var normalizedUnitCost: Double? {
            let trimmed = unitCostText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : Double(trimmed)
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let typeId: Int64
    let brands: [Brand]
    let colors: [PartColor]
    let onSave: (Draft) async throws -> Void

    @State private var selectedColorId: Int64
    @State private var selectedBrandId: Int64
    @State private var partNumber: String
    @State private var unitCostText: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(mode: Mode, typeId: Int64, brands: [Brand], colors: [PartColor], onSave: @escaping (Draft) async throws -> Void) {
        self.mode = mode
        self.typeId = typeId
        self.brands = brands
        self.colors = colors
        self.onSave = onSave

        switch mode {
        case .create:
            _selectedColorId = State(initialValue: colors.first?.id ?? 0)
            _selectedBrandId = State(initialValue: brands.first?.id ?? 0)
            _partNumber = State(initialValue: "")
            _unitCostText = State(initialValue: "")
        case .edit(let row):
            _selectedColorId = State(initialValue: row.sku.colorId)
            _selectedBrandId = State(initialValue: row.sku.brandId)
            _partNumber = State(initialValue: row.sku.partNumber ?? "")
            _unitCostText = State(initialValue: row.sku.unitCost.map { String($0) } ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Variant") {
                    Picker("Variant", selection: $selectedColorId) {
                        ForEach(colors, id: \.id) { color in
                            HStack {
                                Text(color.name)
                                if let partNumber = color.partNumber, !partNumber.isEmpty {
                                    Text(partNumber).foregroundStyle(.secondary)
                                }
                            }
                            .tag(color.id ?? 0)
                        }
                    }
                    .disabled(colors.isEmpty)

                    if let selectedColor {
                        HStack(spacing: DS.Space.sm) {
                            variantPreview(selectedColor)
                            Text(selectedColor.hexCode?.isEmpty == false ? selectedColor.hexCode! : "Named-only variant")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Brand") {
                    Picker("Brand", selection: $selectedBrandId) {
                        ForEach(brands, id: \.id) { brand in
                            Text(brand.name).tag(brand.id ?? 0)
                        }
                    }
                    .disabled(brands.isEmpty)
                }

                Section("SKU Details") {
                    TextField("SKU / manufacturer part number", text: $partNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("Unit cost override", text: $unitCostText)
                        .keyboardType(.decimalPad)
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit SKU Row" : "Add SKU Row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || selectedColorId == 0 || selectedBrandId == 0 || !unitCostIsValid)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var originalSKU: PartsService.ColorBrandSKU? {
        if case .edit(let row) = mode { return row.sku }
        return nil
    }

    private var selectedColor: PartColor? {
        colors.first { $0.id == selectedColorId }
    }

    private var unitCostIsValid: Bool {
        let trimmed = unitCostText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Double(trimmed) != nil
    }

    @ViewBuilder
    private func variantPreview(_ color: PartColor) -> some View {
        HStack(spacing: 6) {
            if let hex = color.hexCode, !hex.isEmpty, let chipColor = Color(hex: hex) {
                Circle().fill(chipColor).frame(width: 12, height: 12)
            } else {
                Image(systemName: "circle.dashed").font(.caption2)
            }
            Text(color.name).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.10))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }

    private func save() async {
        saveError = nil
        guard unitCostIsValid else {
            saveError = "Unit cost must be a number."
            return
        }
        isSaving = true
        do {
            try await onSave(Draft(
                originalSKU: originalSKU,
                colorId: selectedColorId,
                brandId: selectedBrandId,
                partNumber: partNumber,
                unitCostText: unitCostText
            ))
            dismiss()
        } catch {
            saveError = userFriendlyError(error, context: "save SKU row")
        }
        isSaving = false
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
