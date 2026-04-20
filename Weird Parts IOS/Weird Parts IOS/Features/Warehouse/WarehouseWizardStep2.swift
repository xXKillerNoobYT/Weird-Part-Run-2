import SwiftUI
import WiredPartCore

/// Step 2: Place Storage Units — add shelves, racks, gang boxes inline.
struct WarehouseWizardStep2: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    private enum StepSheet: Identifiable {
        case addUnit
        var id: String { "addUnit" }
    }

    @State private var addedUnits: [WarehouseStorageUnit] = []
    @State private var activeSheet: StepSheet?
    @State private var deleteOffsets: IndexSet?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Add your storage units — shelves, pipe racks, gang boxes, etc.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()

            Button {
                activeSheet = .addUnit
            } label: {
                Label("Add Storage Unit", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            if !addedUnits.isEmpty {
                List {
                    ForEach(addedUnits, id: \.id) { unit in
                        HStack {
                            Image(systemName: iconForUnitType(unit.unitType))
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(unit.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(unit.unitType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .onDelete { offsets in
                        deleteOffsets = offsets
                        showDeleteConfirmation = true
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .confirmationDialog(
                    "Remove Storage Unit?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        if let offsets = deleteOffsets { deleteUnits(at: offsets) }
                    }
                    Button("Cancel", role: .cancel) { deleteOffsets = nil }
                } message: {
                    Text("This storage unit will be permanently removed from the floor plan.")
                }
            } else {
                ContentUnavailableView {
                    Label("No Storage Units", systemImage: "cabinet.fill")
                } description: {
                    Text("Tap the button above to add your first shelf, rack, or storage area.")
                }
            }
        }
        .task { loadUnits() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addUnit:
                WizardAddStorageUnitSheet(floorPlanId: floorPlanId) {
                    loadUnits()
                }
            }
        }
    }

    private func loadUnits() {
        do {
            addedUnits = try appCore.warehouseService?.listStorageUnits(floorPlanId: floorPlanId) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load storage units")
        }
    }

    private func deleteUnits(at offsets: IndexSet) {
        for index in offsets {
            guard let unitId = addedUnits[index].id else { continue }
            do {
                try appCore.warehouseService?.deleteStorageUnit(id: unitId)
            } catch {
                stepError = userFriendlyError(error, context: "delete storage unit")
            }
        }
        loadUnits()
    }

    private func iconForUnitType(_ type: String) -> String {
        switch type {
        case "shelf": return "cabinet.fill"
        case "pipe_rack": return "line.3.horizontal"
        case "gang_box": return "shippingbox.fill"
        case "wall_mount": return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case "cabinet": return "door.left.hand.closed"
        case "pallet_rack": return "square.stack.3d.up.fill"
        case "floor_area": return "square.dashed"
        default: return "cube.fill"
        }
    }
}

// MARK: - Add Storage Unit Sheet (Wizard)

struct WizardAddStorageUnitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let floorPlanId: Int64
    var onSave: () -> Void

    @State private var unitName = ""
    @State private var unitType = "shelf"
    @State private var levelCount = 1
    @State private var areasPerLevel = 4
    @State private var saveError: String?
    @State private var isSaving = false

    private let unitTypes: [(String, String, String)] = [
        ("shelf", "Shelf", "cabinet.fill"),
        ("pipe_rack", "Pipe Rack", "line.3.horizontal"),
        ("gang_box", "Gang Box", "shippingbox.fill"),
        ("wall_mount", "Wall Mount", "rectangle.portrait.on.rectangle.portrait.angled.fill"),
        ("cabinet", "Cabinet", "door.left.hand.closed"),
        ("pallet_rack", "Pallet Rack", "square.stack.3d.up.fill"),
        ("floor_area", "Floor Area", "square.dashed"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit Info") {
                    TextField("Name (e.g., Shelf A)", text: $unitName)
                    Picker("Type", selection: $unitType) {
                        ForEach(unitTypes, id: \.0) { type in
                            Label(type.1, systemImage: type.2).tag(type.0)
                        }
                    }
                }

                Section("Structure") {
                    Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...20)
                    Stepper("Areas per Level: \(areasPerLevel)", value: $areasPerLevel, in: 1...50)
                    Text("Total areas: \(levelCount * areasPerLevel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Storage Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { saveUnit() }
                            .disabled(unitName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func saveUnit() {
        isSaving = true
        saveError = nil
        do {
            try appCore.warehouseService?.createStorageUnit(
                floorPlanId: floorPlanId,
                name: unitName.trimmingCharacters(in: .whitespaces),
                unitType: unitType,
                levels: levelCount,
                areasPerLevel: areasPerLevel
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save storage unit")
            isSaving = false
        }
    }
}
