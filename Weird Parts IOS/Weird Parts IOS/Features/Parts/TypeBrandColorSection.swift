import Foundation
import SwiftUI
import WiredPartCore

/// SKU-first editor for a Type's brand + variant catalog rows.
///
/// PE-COLORS Phase 2C replaces the old nested brand -> color picker mental model with
/// flat `color_brand_skus` rows scoped by selected brand. Each row shows:
/// - variant chip (color swatch when `hex_code` exists, text-only pill otherwise)
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

    @State private var allColors: [PartColor] = []
    @State private var skuRows: [ColorBrandSKUDisplayRow] = []
    @State private var selectedBrandId: Int64?
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
                brandChipStrip

                if selectedBrand == nil {
                    noBrandSelectedState
                } else if selectedBrandSKURows.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        ForEach(selectedBrandSKURows) { row in
                            skuRow(row)
                        }
                    }
                }

                Divider()

                HStack(spacing: DS.Space.sm) {
                    Button {
                        activeSheet = .create
                    } label: {
                        Label("Add SKU", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBrand == nil || allColors.isEmpty)

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
        .onChange(of: linkedBrandIds) { _ in
            normalizeSelectedBrand()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                if let selectedBrand {
                    ColorBrandSKUEditorSheet(
                        mode: .create,
                        typeId: typeId,
                        brand: selectedBrand,
                        colors: allColors,
                        onSave: handleSKUSave,
                        onRefreshAfterSave: refreshAfterSKUSave
                    )
                }
            case .edit(let row):
                if let brand = linkedBrands.first(where: { $0.id == row.sku.brandId }) {
                    ColorBrandSKUEditorSheet(
                        mode: .edit(row),
                        typeId: typeId,
                        brand: brand,
                        colors: allColors,
                        onSave: handleSKUSave,
                        onRefreshAfterSave: refreshAfterSKUSave
                    )
                }
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
            if let selectedBrand {
                Text("Delete the SKU row for \(selectedBrand.name) / \(row.color.name)? The type, brand, and variant records stay intact.")
            } else {
                Text("Delete this SKU row? The type, brand, and variant records stay intact.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SKU Rows")
                    .font(.headline)
                Text("Select a brand to manage SKU rows for this type. Each row is a variant + part number + optional cost.")
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

    private var linkedBrands: [Brand] {
        hierarchy.categories
            .flatMap(\.styles)
            .flatMap(\.types)
            .first(where: { $0.type.id == typeId })?
            .brands
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) ?? []
    }

    private var linkedBrandIds: [Int64] {
        linkedBrands.compactMap(\.id)
    }

    private var selectedBrand: Brand? {
        guard let selectedBrandId else { return nil }
        return linkedBrands.first(where: { $0.id == selectedBrandId })
    }

    private var selectedBrandSKURows: [ColorBrandSKUDisplayRow] {
        guard let selectedBrandId else { return [] }
        return skuRows
            .filter { $0.sku.brandId == selectedBrandId }
            .sorted { lhs, rhs in
                lhs.color.name.localizedCaseInsensitiveCompare(rhs.color.name) == .orderedAscending
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

    private var brandChipStrip: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                Text("Brands")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let selectedBrand {
                    Text("Selected: \(selectedBrand.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if linkedBrands.isEmpty {
                Text("No brands linked to this type yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(linkedBrands, id: \.id) { brand in
                            let isSelected = selectedBrandId == brand.id
                            Button {
                                selectedBrandId = isSelected ? nil : brand.id
                            } label: {
                                Text(brand.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var noBrandSelectedState: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("Select a brand to view SKU rows", systemImage: "tag")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("SKU rows are scoped to a specific type + brand + variant combination.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("No SKU rows for selected brand", systemImage: "shippingbox")
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
        if linkedBrands.isEmpty { return "Add brands from the Brands tab before creating brand-specific SKU rows." }
        if allColors.isEmpty { return "Create at least one variant/color before creating SKU rows." }
        return "Use Add SKU to connect a global variant to this selected brand."
    }

    @ViewBuilder
    private func skuRow(_ row: ColorBrandSKUDisplayRow) -> some View {
        Button {
            activeSheet = .edit(row)
        } label: {
            HStack(spacing: DS.Space.sm) {
                variantChip(row.color)

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

    // MARK: - Data Loading

    private func loadSKUData() async {
        guard let service = await MainActor.run(body: { appCore.partsService }) else {
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
            let colors = try service.listColors()
            let skus = try service.getColorBrandSKUsForType(typeId: typeId)
            let colorsById = Dictionary(uniqueKeysWithValues: colors.compactMap { color -> (Int64, PartColor)? in
                guard let id = color.id else { return nil }
                return (id, color)
            })
            let rows = skus.compactMap { sku -> ColorBrandSKUDisplayRow? in
                guard let color = colorsById[sku.colorId] else { return nil }
                return ColorBrandSKUDisplayRow(sku: sku, color: color)
            }

            await MainActor.run {
                allColors = colors
                skuRows = rows
                normalizeSelectedBrand()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load SKU rows")
                isLoading = false
            }
        }
    }

    private func handleSKUSave(_ draft: ColorBrandSKUEditorSheet.Draft) async throws {
        guard let service = await MainActor.run(body: { appCore.partsService }) else {
            throw NSError(domain: "TypeBrandColorSection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }

        try service.linkTypeToColor(typeId: typeId, colorId: draft.colorId)

        let skuId: Int64
        if let original = draft.originalSKU {
            skuId = try service.upsertColorBrandSKU(
                colorId: draft.colorId,
                brandId: draft.brandId,
                typeId: typeId,
                partNumber: draft.normalizedPartNumber,
                unitCost: draft.normalizedUnitCost,
                clearPartNumber: draft.shouldClearPartNumber,
                clearUnitCost: draft.shouldClearUnitCost
            )

            if original.id != skuId, original.colorId != draft.colorId {
                try deleteSKU(service: service, skuId: original.id)
            }
        } else {
            skuId = try createSKU(
                service: service,
                colorId: draft.colorId,
                brandId: draft.brandId,
                partNumber: draft.normalizedPartNumber,
                unitCost: draft.normalizedUnitCost
            )
        }

    }

    private func refreshAfterSKUSave() async {
        await loadSKUData()
        await onRefresh()
    }

    private func deleteSKU(_ row: ColorBrandSKUDisplayRow) async {
        guard let service = await MainActor.run(body: { appCore.partsService }) else {
            await MainActor.run { loadError = "Parts service not available" }
            return
        }
        do {
            try deleteSKU(service: service, skuId: row.sku.id)
            await loadSKUData()
            await onRefresh()
        } catch {
            await MainActor.run { loadError = userFriendlyError(error, context: "delete SKU row") }
        }
    }

    private func createSKU(
        service: PartsService,
        colorId: Int64,
        brandId: Int64,
        partNumber: String?,
        unitCost: Double?
    ) throws -> Int64 {
        try service.upsertColorBrandSKU(
            colorId: colorId,
            brandId: brandId,
            typeId: typeId,
            partNumber: partNumber,
            unitCost: unitCost
        )
    }

    private func deleteSKU(service: PartsService, skuId: Int64) throws {
        try service.deleteColorBrandSKU(skuId: skuId)
    }

    private func normalizeSelectedBrand() {
        if linkedBrands.isEmpty {
            selectedBrandId = nil
            return
        }
        if let selectedBrandId, linkedBrands.contains(where: { $0.id == selectedBrandId }) {
            return
        }
        selectedBrandId = linkedBrands.first?.id
    }
}

private struct ColorBrandSKUDisplayRow: Identifiable, Equatable {
    let sku: PartsService.ColorBrandSKU
    let color: PartColor

    var id: Int64 { sku.id }

    var partNumberDisplay: String {
        let value = sku.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "No SKU part number" : value
    }

    static func == (lhs: ColorBrandSKUDisplayRow, rhs: ColorBrandSKUDisplayRow) -> Bool {
        lhs.id == rhs.id && lhs.sku.colorId == rhs.sku.colorId && lhs.sku.brandId == rhs.sku.brandId
    }
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
            return trimmed.isEmpty ? nil : parseLocalizedDecimal(trimmed)
        }

        var shouldClearPartNumber: Bool {
            originalSKU?.partNumber != nil && normalizedPartNumber == nil
        }

        var shouldClearUnitCost: Bool {
            originalSKU?.unitCost != nil && normalizedUnitCost == nil
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let typeId: Int64
    let brand: Brand
    let colors: [PartColor]
    let onSave: (Draft) async throws -> Void
    let onRefreshAfterSave: () async -> Void

    @State private var selectedColorId: Int64
    @State private var partNumber: String
    @State private var unitCostText: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        mode: Mode,
        typeId: Int64,
        brand: Brand,
        colors: [PartColor],
        onSave: @escaping (Draft) async throws -> Void,
        onRefreshAfterSave: @escaping () async -> Void
    ) {
        self.mode = mode
        self.typeId = typeId
        self.brand = brand
        self.colors = colors
        self.onSave = onSave
        self.onRefreshAfterSave = onRefreshAfterSave

        switch mode {
        case .create:
            _selectedColorId = State(initialValue: colors.first(where: { $0.id != nil })?.id ?? 0)
            _partNumber = State(initialValue: "")
            _unitCostText = State(initialValue: "")
        case .edit(let row):
            _selectedColorId = State(initialValue: row.sku.colorId)
            _partNumber = State(initialValue: row.sku.partNumber ?? "")
            _unitCostText = State(initialValue: row.sku.unitCost.map(formatLocalizedDecimal) ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Variant") {
                    Picker("Variant", selection: $selectedColorId) {
                        ForEach(selectableColors, id: \.id) { color in
                            HStack {
                                Text(color.name)
                                if let partNumber = color.partNumber, !partNumber.isEmpty {
                                    Text(partNumber).foregroundStyle(.secondary)
                                }
                            }
                            .tag(color.id!)
                        }
                    }
                    .disabled(selectableColors.isEmpty)

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
                    Text(brand.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
            .navigationTitle(isEditing ? "Edit SKU" : "Add SKU")
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
                    .disabled(isSaving || selectedColorId == 0 || !unitCostIsValid)
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

    private var selectableColors: [PartColor] {
        colors.filter { $0.id != nil }
    }

    private var selectedColor: PartColor? {
        colors.first { $0.id == selectedColorId }
    }

    private var unitCostIsValid: Bool {
        let trimmed = unitCostText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || parseLocalizedDecimal(trimmed) != nil
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
        guard let brandId = brand.id else {
            saveError = "Selected brand is invalid."
            return
        }
        isSaving = true
        do {
            try await onSave(Draft(
                originalSKU: originalSKU,
                colorId: selectedColorId,
                brandId: brandId,
                partNumber: partNumber,
                unitCostText: unitCostText
            ))
            dismiss()
            await onRefreshAfterSave()
            isSaving = false
        } catch {
            saveError = userFriendlyError(error, context: "save SKU row")
            isSaving = false
        }
    }
}

private func parseLocalizedDecimal(_ text: String) -> Double? {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .current
    return formatter.number(from: text.trimmingCharacters(in: .whitespacesAndNewlines))?.doubleValue
}

private func formatLocalizedDecimal(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .current
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

// MARK: - BrandFlowLayout (wrapping horizontal layout)

/// A simple flow layout that wraps children to the next line when they don't fit.
/// Alias to the shared `FlowChipLayout`, whose geometry (`FlowLayoutMath` in core)
/// always reports a finite measured size (#1203).
typealias BrandFlowLayout = FlowChipLayout
