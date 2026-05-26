import SwiftUI
import WiredPartCore

/// Wizard Step 6: Define Areas on Shelves — sections within each shelf.
///
/// For each shelf, the user can view existing areas (auto-generated or manual)
/// and mark them as "open storage" (multiple parts) or "bins" (individual boxes).
struct WizardStepAreas: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var units: [WarehouseStorageUnit] = []
    @State private var unitLevels: [Int64: [WarehouseStorageLevel]] = [:]
    @State private var levelAreas: [Int64: [WarehouseStorageArea]] = [:]
    @State private var expandedLevelId: Int64?
    @State private var showAddArea: Int64?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Areas are sections within each shelf. Mark them as open storage or bins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Open storage holds multiple parts. Bin areas have numbered individual boxes.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()

            if units.isEmpty {
                EmptyStateView(
                    icon: "cabinet.fill",
                    title: "No Storage Units",
                    message: "Add storage units in Step 3 first."
                )
            } else {
                List {
                    ForEach(units, id: \.id) { unit in
                        unitSection(unit)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { loadData() }
        .sheet(item: Binding(
            get: { showAddArea.map { AddAreaTarget(levelId: $0) } },
            set: { showAddArea = $0?.levelId }
        )) { target in
            AddAreaSheet(levelId: target.levelId) {
                loadAreas(for: target.levelId)
            }
        }
    }

    // MARK: - Unit Section

    @ViewBuilder
    private func unitSection(_ unit: WarehouseStorageUnit) -> some View {
        let unitId = unit.id ?? 0
        let levels = unitLevels[unitId] ?? []

        Section(unit.name) {
            ForEach(levels, id: \.id) { level in
                levelRow(level, unitName: unit.name)
            }
        }
    }

    @ViewBuilder
    private func levelRow(_ level: WarehouseStorageLevel, unitName: String) -> some View {
        let levelId = level.id ?? 0
        let areas = levelAreas[levelId] ?? []
        let isExpanded = expandedLevelId == level.id

        // Level header
        Button {
            withAnimation {
                expandedLevelId = isExpanded ? nil : level.id
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("\(unitName) — \(level.levelCode)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(areas.count) area(s)")
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
            ForEach(areas, id: \.id) { area in
                HStack {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(area.fullLocationCode ?? area.areaCode)
                            .font(.caption)
                            .monospaced()
                        Text("Area \(area.areaNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.leading, 12)
            }

            Button {
                showAddArea = levelId
            } label: {
                Label("Add Area", systemImage: "plus.circle")
                    .font(.caption)
            }
            .padding(.leading, 12)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        do {
            units = try appCore.warehouseService?.listStorageUnits(floorPlanId: floorPlanId) ?? []
            for unit in units {
                guard let unitId = unit.id else { continue }
                let levels = try appCore.warehouseService?.listLevelsForUnit(unitId: unitId) ?? []
                unitLevels[unitId] = levels
                for level in levels {
                    guard let levelId = level.id else { continue }
                    loadAreas(for: levelId)
                }
            }
        } catch {
            stepError = userFriendlyError(error, context: "load areas")
        }
    }

    private func loadAreas(for levelId: Int64) {
        do {
            levelAreas[levelId] = try appCore.warehouseService?.listAreasForLevel(levelId: levelId) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load areas for level")
        }
    }
}

// MARK: - Helper

private struct AddAreaTarget: Identifiable {
    let levelId: Int64
    var id: Int64 { levelId }
}

// MARK: - Add Area Sheet

struct AddAreaSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let levelId: Int64
    var onSave: () -> Void

    @State private var areaCount = 1
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("How many areas?") {
                    Stepper("Areas: \(areaCount)", value: $areaCount, in: 1...20)
                    Text("Each area gets an auto-generated code. You can label them later.")
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
            .navigationTitle("Add Areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                }
            }
        }
    }

    private func save() {
        do {
            // Find the next area number
            let existing = try appCore.warehouseService?.listAreasForLevel(levelId: levelId) ?? []
            let maxNumber = existing.map(\.areaNumber).max() ?? 0

            for i in 1...areaCount {
                _ = try appCore.warehouseService?.addStorageArea(
                    levelId: levelId,
                    areaNumber: maxNumber + i
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "add areas")
        }
    }
}
