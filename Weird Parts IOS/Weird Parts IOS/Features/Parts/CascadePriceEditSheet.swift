import SwiftUI
import WiredPartCore

/// Cascade price editor for a specific color within a type.
///
/// Shows the three-level cost cascade:
/// 1. **Type Default** — base cost inherited by all colors of this type
/// 2. **Color Override** — specific cost for this color (overrides type default)
/// 3. **Supplier Costs** — per-supplier cost for this color (overrides color cost)
///
/// The effective price resolves: Supplier → Color → Type → none.
struct CascadePriceEditSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let colorId: Int64
    let typeId: Int64
    var onSave: (() -> Void)?

    // State
    @State private var typeName = ""
    @State private var colorName = ""
    @State private var typeDefaultCostText = ""
    @State private var colorOverrideCostText = ""
    @State private var supplierCosts: [PartsService.ColorSupplierCostRow] = []
    @State private var resolvedCost: PartsService.ResolvedCascadeCost?
    @State private var isLoading = true

    // Add supplier cost
    @State private var showAddSupplier = false
    @State private var allSuppliers: [PartsService.SupplierWithCount] = []
    @State private var selectedSupplierId: Int64?
    @State private var newSupplierCostText = ""

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        ProgressView("Loading pricing...")
                    }
                } else {
                    effectivePriceSection
                    typeDefaultSection
                    colorOverrideSection
                    supplierCostsSection
                }
            }
            .navigationTitle("Edit Cost — \(colorName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAll() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - Effective Price Summary

    private var effectivePriceSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Effective Cost")
                        .font(.headline)
                    if let resolved = resolvedCost {
                        Text("Source: \(resolved.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let cost = resolvedCost?.effectiveCost {
                    Text(cost, format: .currency(code: "USD"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                } else {
                    Text("No price set")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Summary")
        } footer: {
            Text("Cascade: Supplier Cost → Color Override → Type Default")
        }
    }

    // MARK: - Type Default

    private var typeDefaultSection: some View {
        Section {
            HStack {
                Text("Default cost for all colors of")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(typeName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $typeDefaultCostText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("typeDefaultCostField")
                if !typeDefaultCostText.isEmpty {
                    Button {
                        typeDefaultCostText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Label("Type Default", systemImage: "square.stack.3d.up")
        } footer: {
            Text("All colors of this type inherit this cost unless overridden.")
        }
    }

    // MARK: - Color Override

    private var colorOverrideSection: some View {
        Section {
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Inherits from type", text: $colorOverrideCostText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("colorOverrideCostField")
                if !colorOverrideCostText.isEmpty {
                    Button {
                        colorOverrideCostText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Label("Color Override", systemImage: "paintpalette")
        } footer: {
            Text("Set a specific cost for this color. Leave empty to inherit the type default.")
        }
    }

    // MARK: - Supplier Costs

    private var supplierCostsSection: some View {
        Section {
            if supplierCosts.isEmpty {
                Text("No supplier-specific costs set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(supplierCosts, id: \.id) { row in
                    HStack {
                        Text(row.supplierName)
                            .font(.subheadline)
                        Spacer()
                        Text(row.cost, format: .currency(code: "USD"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removeSupplierCost(row)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showAddSupplier = true
                loadSuppliers()
            } label: {
                Label("Add Supplier Cost", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } header: {
            Label("Supplier Costs", systemImage: "building.2")
        } footer: {
            Text("When ordering from a specific supplier, their cost takes priority over the color and type costs.")
        }
        .sheet(isPresented: $showAddSupplier) {
            addSupplierCostSheet
        }
    }

    // MARK: - Add Supplier Cost Sheet

    private var addSupplierCostSheet: some View {
        NavigationStack {
            Form {
                Section("Select Supplier") {
                    // Filter out suppliers that already have a cost set
                    let existingIds = Set(supplierCosts.map(\.supplierId))
                    let available = allSuppliers.filter { !existingIds.contains($0.supplier.id ?? 0) }

                    if available.isEmpty {
                        Text("All suppliers already have costs assigned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(available, id: \.supplier.id) { swc in
                            Button {
                                selectedSupplierId = swc.supplier.id
                            } label: {
                                HStack {
                                    Text(swc.supplier.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedSupplierId == swc.supplier.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                if selectedSupplierId != nil {
                    Section("Cost") {
                        HStack {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $newSupplierCostText)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("Add Supplier Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSupplier = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSupplierCost()
                        showAddSupplier = false
                    }
                    .disabled(selectedSupplierId == nil || newSupplierCostText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let parts = appCore.partsService else { return }

        do {
            // Load type and color names
            let partType = try parts.getType(id: typeId)
            typeName = partType.name

            let colors = try parts.listColors()
            let color = colors.first(where: { $0.id == colorId })
            colorName = color?.name ?? "Color"

            // Load resolved pricing
            resolvedCost = try parts.getEffectivePrice(colorId: colorId, typeId: typeId)

            // Populate fields from resolved data
            if let typeCost = resolvedCost?.typeDefaultCost {
                typeDefaultCostText = String(format: "%.2f", typeCost)
            }
            if let colorCost = resolvedCost?.colorOverrideCost {
                colorOverrideCostText = String(format: "%.2f", colorCost)
            }

            // Load supplier-specific costs
            supplierCosts = try parts.getColorSupplierCosts(colorId: colorId)
        } catch {
            // Non-fatal — show what we can
        }

        isLoading = false
    }

    private func loadSuppliers() {
        guard let parts = appCore.partsService else { return }
        allSuppliers = (try? parts.listSuppliers()) ?? []
    }

    // MARK: - Save

    private func saveAll() {
        guard let parts = appCore.partsService else { return }

        do {
            // Save type default cost
            let typeCost = Double(typeDefaultCostText)
            try parts.setPriceForType(typeId: typeId, unitCost: typeCost)

            // Save color override cost
            let colorCost = Double(colorOverrideCostText)
            try parts.setPriceForColor(colorId: colorId, unitCost: colorCost)

            onSave?()
            dismiss()
        } catch {
            // Error handling — sheet stays open
        }
    }

    // MARK: - Supplier Cost Actions

    private func addSupplierCost() {
        guard let parts = appCore.partsService,
              let suppId = selectedSupplierId,
              let cost = Double(newSupplierCostText) else { return }

        do {
            try parts.setSupplierCostForColor(colorId: colorId, supplierId: suppId, cost: cost)
            supplierCosts = (try? parts.getColorSupplierCosts(colorId: colorId)) ?? supplierCosts
            resolvedCost = try? parts.getEffectivePrice(colorId: colorId, typeId: typeId)

            // Reset add form
            selectedSupplierId = nil
            newSupplierCostText = ""
        } catch {
            // Non-fatal
        }
    }

    private func removeSupplierCost(_ row: PartsService.ColorSupplierCostRow) {
        guard let parts = appCore.partsService else { return }

        do {
            try parts.removeSupplierCostForColor(colorId: colorId, supplierId: row.supplierId)
            supplierCosts = (try? parts.getColorSupplierCosts(colorId: colorId)) ?? supplierCosts
            resolvedCost = try? parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        } catch {
            // Non-fatal
        }
    }
}
