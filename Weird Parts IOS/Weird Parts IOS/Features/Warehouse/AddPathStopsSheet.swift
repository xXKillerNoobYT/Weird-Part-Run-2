import SwiftUI
import WiredPartCore

struct WalkingPathAreaInfo: Identifiable, Hashable {
    let id: Int64
    let areaCode: String
    let fullLocationCode: String
    let unitName: String
    let unitNumber: String
    let levelCode: String
    let zoneName: String
}

struct AddPathStopsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let areas: [WalkingPathAreaInfo]
    let existingAreaIds: Set<Int64>
    let onAdd: ([Int64]) -> Void

    @State private var selectedAreaIds: Set<Int64> = []
    @State private var searchText = ""

    private var filteredAreas: [WalkingPathAreaInfo] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return areas
        }
        let query = searchText.lowercased()
        return areas.filter {
            $0.fullLocationCode.lowercased().contains(query) ||
            $0.unitName.lowercased().contains(query) ||
            $0.zoneName.lowercased().contains(query)
        }
    }

    private var groupedAreas: [(zone: String, units: [(unit: String, levels: [(level: String, areas: [WalkingPathAreaInfo])])])] {
        Dictionary(grouping: filteredAreas, by: \.zoneName)
            .keys
            .sorted()
            .map { zone in
                let zoneAreas = filteredAreas.filter { $0.zoneName == zone }
                let units = Dictionary(grouping: zoneAreas, by: { "\($0.unitNumber) · \($0.unitName)" })
                    .keys
                    .sorted()
                    .map { unit in
                        let unitAreas = zoneAreas.filter { "\($0.unitNumber) · \($0.unitName)" == unit }
                        let levels = Dictionary(grouping: unitAreas, by: \.levelCode)
                            .keys
                            .sorted()
                            .map { level in
                                (
                                    level: level,
                                    areas: unitAreas
                                        .filter { $0.levelCode == level }
                                        .sorted { $0.areaCode < $1.areaCode }
                                )
                            }
                        return (unit: unit, levels: levels)
                    }
                return (zone: zone, units: units)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedAreas, id: \.zone) { zoneGroup in
                    Section(zoneGroup.zone) {
                        ForEach(zoneGroup.units, id: \.unit) { unitGroup in
                            DisclosureGroup(unitGroup.unit) {
                                ForEach(unitGroup.levels, id: \.level) { levelGroup in
                                    DisclosureGroup("Level \(levelGroup.level)") {
                                        ForEach(levelGroup.areas) { area in
                                            Button {
                                                toggle(area.id)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    Image(systemName: selectedAreaIds.contains(area.id) ? "checkmark.circle.fill" : "circle")
                                                        .foregroundStyle(selectedAreaIds.contains(area.id) ? .blue : .secondary)
                                                        .accessibilityHidden(true)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(area.fullLocationCode)
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                        Text(area.areaCode)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    if existingAreaIds.contains(area.id) {
                                                        Text("On path")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Stops")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search areas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedAreaIds.count)") {
                        let ordered = areas.map(\.id).filter { selectedAreaIds.contains($0) }
                        onAdd(ordered)
                        dismiss()
                    }
                    .disabled(selectedAreaIds.isEmpty)
                }
            }
        }
    }

    private func toggle(_ areaId: Int64) {
        if selectedAreaIds.contains(areaId) {
            selectedAreaIds.remove(areaId)
        } else if !existingAreaIds.contains(areaId) {
            selectedAreaIds.insert(areaId)
        }
    }
}
