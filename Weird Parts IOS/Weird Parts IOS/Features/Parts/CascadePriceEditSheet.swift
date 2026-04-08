import SwiftUI
import WiredPartCore

/// Cascade pricing editor for a specific color within a type.
///
/// Shows the 3-level pricing cascade:
///   1. Type Default — applies to all colors of this type unless overridden
///   2. Color Override — overrides the type default for this specific color
///   3. Supplier Costs — per-supplier cost for this color (used on POs)
///
/// Also shows price history if data exists.
struct CascadePriceEditSheet: View {
    let colorId: Int64
    var colorName: String = ""
    let typeId: Int64?
    var typeName: String? = nil
    let onSave: () async -> Void

    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var typeDefaultText = ""
    @State private var colorOverrideText = ""
    @State private var supplierCosts: [SupplierCostEntry] = []
    @State private var resolvedCost: PartsService.ResolvedCascadeCost?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var loadError: String?
    @State private var displayColorName = ""
    @State private var displayTypeName: String?

    /// Local model for editing supplier costs inline.
    struct SupplierCostEntry: Identifiable {
        let id: Int64
        let supplierId: Int64
        let supplierName: String
        var costText: String
        var notes: String?
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading pricing...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { Task { await loadData() } }
                } else {
                    formContent
                }
            }
            .navigationTitle("Pricing")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadData() }
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        Form {
            // Header
            Section {
                LabeledContent("Color", value: displayColorName.isEmpty ? "Color #\(colorId)" : displayColorName)
                if let tName = displayTypeName {
                    LabeledContent("Type", value: tName)
                }
                if let resolved = resolvedCost {
                    HStack {
                        Text("Effective Cost")
                        Spacer()
                        if let cost = resolved.effectiveCost {
                            Text(String(format: "$%.2f", cost))
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            sourceBadge(resolved.source)
                        } else {
                            Text("No price")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Type Default
            Section {
                HStack {
                    Text("Default Cost")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $typeDefaultText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .keyboardType(.decimalPad)
                }
                .frame(minHeight: 44)

                Button("Save Type Default") {
                    Task { await saveTypeDefault() }
                }
                .disabled(isSaving)
            } header: {
                Text("Type Default")
            } footer: {
                Text("Applies to all colors of this type unless overridden.")
            }

            // Color Override
            Section {
                HStack {
                    Text("Override Cost")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $colorOverrideText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .keyboardType(.decimalPad)
                }
                .frame(minHeight: 44)

                if colorOverrideText.isEmpty, let typeCost = resolvedCost?.typeDefaultCost {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(String(format: "Inheriting $%.2f from type", typeCost))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }

                HStack {
                    Button("Save Color Override") {
                        Task { await saveColorOverride() }
                    }
                    .disabled(isSaving)

                    Spacer()

                    if resolvedCost?.colorOverrideCost != nil {
                        Button("Clear Override", role: .destructive) {
                            Task { await clearColorOverride() }
                        }
                        .disabled(isSaving)
                    }
                }
            } header: {
                Text("This Color Override")
            } footer: {
                Text("Overrides the type default for this specific color only.")
            }

            // Supplier Costs
            if !supplierCosts.isEmpty {
                Section {
                    DisclosureGroup("Supplier Costs (\(supplierCosts.count))") {
                        ForEach($supplierCosts) { $entry in
                            HStack {
                                Text(entry.supplierName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text("$")
                                    .foregroundStyle(.secondary)
                                TextField("0.00", text: $entry.costText)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 100)
                                    .keyboardType(.decimalPad)
                                Button {
                                    Task { await saveSupplierCost(entry) }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSaving)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } header: {
                    Text("Cost Per Supplier")
                } footer: {
                    Text("Supplier-specific costs used when generating purchase orders.")
                }
            }

            // Error display
            if let error = saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Source Badge

    @ViewBuilder
    private func sourceBadge(_ source: String) -> some View {
        Text(source)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sourceColor(source).opacity(0.15))
            .foregroundStyle(sourceColor(source))
            .clipShape(Capsule())
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "supplier": return .purple
        case "color": return .blue
        case "type": return .orange
        default: return .secondary
        }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        guard let service = appCore.partsService else {
            await MainActor.run { loadError = "Service not available"; isLoading = false }
            return
        }

        do {
            // Resolve names if not provided
            var cName = colorName
            var tName = typeName
            if cName.isEmpty {
                let colors = try service.listColors()
                cName = colors.first(where: { $0.id == colorId })?.name ?? "Color #\(colorId)"
            }
            if tName == nil, let tId = typeId {
                let types = try service.listTypes()
                tName = types.first(where: { $0.id == tId })?.name
            }

            let resolved = try service.getEffectivePrice(colorId: colorId, typeId: typeId)
            let costs = try service.getColorSupplierCosts(colorId: colorId)

            let entries = costs.map { row in
                SupplierCostEntry(
                    id: row.id,
                    supplierId: row.supplierId,
                    supplierName: row.supplierName,
                    costText: String(format: "%.2f", row.cost),
                    notes: row.notes
                )
            }

            await MainActor.run {
                displayColorName = cName
                displayTypeName = tName
                resolvedCost = resolved
                typeDefaultText = resolved.typeDefaultCost.map { String(format: "%.2f", $0) } ?? ""
                colorOverrideText = resolved.colorOverrideCost.map { String(format: "%.2f", $0) } ?? ""
                supplierCosts = entries
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load pricing data")
                isLoading = false
            }
        }
    }

    // MARK: - Save Actions

    private func saveTypeDefault() async {
        guard let service = appCore.partsService, let tId = typeId else {
            saveError = "Type not available"
            return
        }

        isSaving = true
        saveError = nil
        do {
            let cost = Double(typeDefaultText)
            try service.setPriceForType(typeId: tId, unitCost: cost)
            await onSave()
            await loadData()
        } catch {
            saveError = userFriendlyError(error, context: "save type default")
        }
        isSaving = false
    }

    private func saveColorOverride() async {
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        isSaving = true
        saveError = nil
        do {
            let cost = Double(colorOverrideText)
            try service.setPriceForColor(colorId: colorId, unitCost: cost)
            await onSave()
            await loadData()
        } catch {
            saveError = userFriendlyError(error, context: "save color override")
        }
        isSaving = false
    }

    private func clearColorOverride() async {
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        isSaving = true
        saveError = nil
        do {
            try service.setPriceForColor(colorId: colorId, unitCost: nil)
            colorOverrideText = ""
            await onSave()
            await loadData()
        } catch {
            saveError = userFriendlyError(error, context: "clear color override")
        }
        isSaving = false
    }

    private func saveSupplierCost(_ entry: SupplierCostEntry) async {
        guard let service = appCore.partsService else {
            saveError = "Service not available"
            return
        }

        isSaving = true
        saveError = nil
        do {
            guard let cost = Double(entry.costText), cost > 0 else {
                saveError = "Invalid cost value"
                isSaving = false
                return
            }
            try service.setSupplierCostForColor(
                colorId: colorId,
                supplierId: entry.supplierId,
                cost: cost,
                notes: entry.notes
            )
            await onSave()
            await loadData()
        } catch {
            saveError = userFriendlyError(error, context: "save supplier cost")
        }
        isSaving = false
    }
}
