import SwiftUI
import WiredPartCore

/// Wizard Step 5: Define Shelves — for each storage unit, add shelves (levels).
///
/// Shows all units created in Step 3. For each unit, the user can
/// view/add/rename shelves. Auto-generated shelves from `createStorageUnit`
/// are shown and can be customized.
struct WizardStepShelves: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var units: [WarehouseStorageUnit] = []
    @State private var expandedUnitId: Int64?
    @State private var unitLevels: [Int64: [WarehouseStorageLevel]] = [:]
    @State private var showAddLevel: Int64?

    // Add level state
    @State private var newLevelCode = ""
    @State private var newLevelName = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Each storage unit has shelves (levels). Review and customize them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Shelves created during Step 3 appear here automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()

            if units.isEmpty {
                ContentUnavailableView {
                    Label("No Storage Units", systemImage: "cabinet.fill")
                } description: {
                    Text("Add storage units in Step 3 first.")
                }
            } else {
                List {
                    ForEach(units, id: \.id) { unit in
                        unitSection(unit)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task { loadData() }
        .sheet(item: Binding(
            get: { showAddLevel.map { AddLevelTarget(unitId: $0) } },
            set: { showAddLevel = $0?.unitId }
        )) { target in
            AddLevelSheet(unitId: target.unitId) {
                loadLevels(for: target.unitId)
            }
        }
    }

    // MARK: - Unit Section

    @ViewBuilder
    private func unitSection(_ unit: WarehouseStorageUnit) -> some View {
        let unitId = unit.id ?? 0
        let levels = unitLevels[unitId] ?? []
        let isExpanded = expandedUnitId == unit.id

        Section {
            // Unit header
            Button {
                withAnimation {
                    expandedUnitId = isExpanded ? nil : unit.id
                }
            } label: {
                HStack {
                    Image(systemName: "cabinet.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(unit.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("\(levels.count) shelf/shelves")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Shelves list
                ForEach(levels, id: \.id) { level in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.teal)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(level.levelCode)
                                .font(.subheadline)
                                .monospaced()
                            if let name = level.levelName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("Order: \(level.levelOrder)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 8)
                }

                // Add shelf button
                Button {
                    showAddLevel = unitId
                } label: {
                    Label("Add Shelf", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        do {
            units = try appCore.warehouseService?.listStorageUnits(floorPlanId: floorPlanId) ?? []
            for unit in units {
                if let unitId = unit.id {
                    loadLevels(for: unitId)
                }
            }
            // Auto-expand first unit
            expandedUnitId = units.first?.id
        } catch {
            stepError = userFriendlyError(error, context: "load units")
        }
    }

    private func loadLevels(for unitId: Int64) {
        do {
            unitLevels[unitId] = try appCore.warehouseService?.listLevelsForUnit(unitId: unitId) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load shelves")
        }
    }
}

// MARK: - Helper

private struct AddLevelTarget: Identifiable {
    let unitId: Int64
    var id: Int64 { unitId }
}

// MARK: - Add Level Sheet

struct AddLevelSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let unitId: Int64
    var onSave: () -> Void

    @State private var levelCode = ""
    @State private var levelName = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Shelf Info") {
                    TextField("Code (e.g., S01, Top, Bottom)", text: $levelCode)
                    TextField("Name (optional)", text: $levelName)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(levelCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            let name = levelName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : levelName.trimmingCharacters(in: .whitespaces)
            _ = try appCore.warehouseService?.addStorageLevel(
                unitId: unitId,
                levelCode: levelCode.trimmingCharacters(in: .whitespaces),
                levelName: name
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "add shelf")
        }
    }
}
