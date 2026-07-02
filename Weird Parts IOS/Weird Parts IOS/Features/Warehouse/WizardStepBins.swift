import SwiftUI
import WiredPartCore

/// Wizard Step 7: Bin Numbers — create numbered bins in bin-type areas.
///
/// For each area, the user can create bins. The system auto-assigns bin
/// numbers (e.g., B-001, B-002). Users can rename bins afterward.
/// Bins are NOT location-locked — they can be moved at any time.
struct WizardStepBins: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var allAreas: [WizardAreaInfo] = []
    @State private var areaBins: [Int64: [WarehouseBin]] = [:]
    @State private var expandedAreaId: Int64?
    @State private var showAddBins: Int64?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Add numbered bins to your areas. Bins are small boxes that hold individual parts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("Bins are portable — they can be moved between shelves at any time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()

            if allAreas.isEmpty {
                EmptyStateView(
                    icon: "tray.fill",
                    title: "No Areas Yet",
                    message: "Create storage units with levels and areas in earlier steps first."
                )
            } else {
                List {
                    ForEach(allAreas) { area in
                        areaSection(area)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { loadData() }
        .sheet(item: Binding(
            get: { showAddBins.map { AddBinsTarget(areaId: $0) } },
            set: { showAddBins = $0?.areaId }
        )) { target in
            AddBinsSheet(areaId: target.areaId) {
                loadBins(for: target.areaId)
            }
        }
    }

    // MARK: - Area Section

    @ViewBuilder
    private func areaSection(_ area: WizardAreaInfo) -> some View {
        let bins = areaBins[area.id] ?? []
        let isExpanded = expandedAreaId == area.id

        Section {
            // Area header
            Button {
                withAnimation {
                    expandedAreaId = isExpanded ? nil : area.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.fullLocationCode)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospaced()
                            .foregroundStyle(.primary)
                        Text("\(area.unitName) — \(area.levelCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !bins.isEmpty {
                        Text("\(bins.count) bins")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if bins.isEmpty {
                    Text("No bins in this area")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                } else {
                    ForEach(bins, id: \.id) { bin in
                        HStack {
                            Image(systemName: "tray.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(bin.binCode)
                                .font(.subheadline)
                                .monospaced()
                            Spacer()
                            if bin.assignedPartId != nil {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .accessibilityLabel("Part assigned")
                            }
                        }
                        .padding(.leading, 8)
                    }
                }

                Button {
                    showAddBins = area.id
                } label: {
                    Label("Add Bins", systemImage: "plus.circle")
                        .font(.caption)
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        do {
            guard let service = appCore.warehouseService else {
                stepError = "Warehouse service not available"
                return
            }
            allAreas = try loadAllWizardAreas(floorPlanId: floorPlanId, service: service)
            for area in allAreas {
                loadBins(for: area.id)
            }
            // Auto-expand first area
            expandedAreaId = allAreas.first?.id
        } catch {
            stepError = userFriendlyError(error, context: "load areas for bins")
        }
    }

    private func loadBins(for areaId: Int64) {
        do {
            areaBins[areaId] = try appCore.warehouseService?.listBinsForArea(areaId: areaId) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load bins")
        }
    }
}

// MARK: - Helper

private struct AddBinsTarget: Identifiable {
    let areaId: Int64
    var id: Int64 { areaId }
}

// MARK: - Add Bins Sheet

struct AddBinsSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let areaId: Int64
    var onSave: () -> Void

    @State private var binCount = 5
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Number of Bins") {
                    Stepper("Bins: \(binCount)", value: $binCount, in: 1...50)
                    Text("Bins are auto-numbered (e.g., B01, B02...). You can rename them later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(1...min(binCount, 5), id: \.self) { i in
                                Text("B\(String(format: "%02d", i))")
                                    .font(.caption2)
                                    .monospaced()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            if binCount > 5 {
                                Text("...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Bins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create \(binCount) Bins") { save() }
                }
            }
        }
    }

    private func save() {
        do {
            // Find the next bin number
            let existing = try appCore.warehouseService?.listBinsForArea(areaId: areaId) ?? []
            let maxNumber = existing.map(\.binNumber).max() ?? 0

            for i in 1...binCount {
                _ = try appCore.warehouseService?.addBin(
                    areaId: areaId,
                    binNumber: maxNumber + i
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "create bins")
        }
    }
}
