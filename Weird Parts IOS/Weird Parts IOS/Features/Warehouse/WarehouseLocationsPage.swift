import SwiftUI
import GRDB
import WiredPartCore

/// Inventory by location — shows all stock grouped by location type and ID.
///
/// Presents sections for each location type (Warehouse, Trucks, Trailers,
/// Jobs, Staged/Pulled). Each section lists parts with their quantities.
/// Supports search across all locations and pull-to-refresh.
struct WarehouseLocationsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var locationStock: [WarehouseService.LocationStock] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedLocation: LocationGroup?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading locations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedLocations.isEmpty {
                emptyState
            } else {
                locationsList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts across all locations...")
        .refreshable { await loadData() }
        .sheet(item: $selectedLocation) { group in
            LocationDetailSheet(group: group)
        }
        #if os(iOS)
        .background(DS.Background.page)
        #elseif os(macOS)
        .background(DS.Background.page)
        #endif
        .task { await loadData() }
    }

    // MARK: - Grouped Locations

    /// Group stock entries by location type, then by location ID within each type.
    private var groupedLocations: [LocationTypeSection] {
        let filtered: [WarehouseService.LocationStock]
        if searchText.isEmpty {
            filtered = locationStock
        } else {
            let query = searchText.lowercased()
            filtered = locationStock.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.partCode?.lowercased().contains(query) ?? false)
            }
        }

        // Group by location type
        let byType = Dictionary(grouping: filtered) { $0.locationType }

        // Sort types in display order
        let typeOrder = ["warehouse", "truck", "trailer", "job", "staging", "pulled"]
        let sortedTypes = byType.keys.sorted { a, b in
            let ai = typeOrder.firstIndex(of: a) ?? typeOrder.count
            let bi = typeOrder.firstIndex(of: b) ?? typeOrder.count
            return ai < bi
        }

        return sortedTypes.map { locType in
            let items = byType[locType]!
            // Group by location ID within this type
            let byId = Dictionary(grouping: items) { $0.locationId }
            let groups = byId.keys.sorted().map { locId in
                LocationGroup(
                    locationType: locType,
                    locationId: locId,
                    items: byId[locId]!,
                    totalQty: byId[locId]!.reduce(0) { $0 + $1.qty }
                )
            }
            return LocationTypeSection(
                locationType: locType,
                groups: groups,
                totalQty: groups.reduce(0) { $0 + $1.totalQty }
            )
        }
    }

    // MARK: - Locations List

    @ViewBuilder
    private var locationsList: some View {
        List {
            ForEach(groupedLocations) { section in
                Section {
                    ForEach(section.groups) { group in
                        Button {
                            selectedLocation = group
                        } label: {
                            locationGroupRow(group)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Image(systemName: locationIcon(section.locationType))
                        Text(locationTypeLabel(section.locationType))
                            .textCase(.uppercase)
                        Spacer()
                        Text("\(section.totalQty) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func locationGroupRow(_ group: LocationGroup) -> some View {
        HStack(spacing: 12) {
            // Location icon
            VStack {
                Image(systemName: locationIcon(group.locationType))
                    .font(.title3)
                    .foregroundStyle(locationColor(group.locationType))
            }
            .frame(width: 40, height: 40)
            #if os(iOS)
            .background(locationColor(group.locationType).opacity(0.12))
            #elseif os(macOS)
            .background(locationColor(group.locationType).opacity(0.12))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(locationTypeLabel(group.locationType)) #\(group.locationId)")
                    .font(.body)
                    .fontWeight(.medium)
                Text("\(group.items.count) part\(group.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(group.totalQty)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("total qty")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 56)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Stock Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Stock entries will appear here grouped by their storage location.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            guard let service = appCore.warehouseService else {
                await MainActor.run { isLoading = false }
                return
            }
            let fetched = try service.getLocationStock()
            await MainActor.run {
                locationStock = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Helpers

    private func locationIcon(_ type: String) -> String {
        switch type {
        case "warehouse": return "building.fill"
        case "truck": return "truck.box.fill"
        case "trailer": return "truck.box.badge.clock.fill"
        case "job": return "hammer.fill"
        case "staging", "pulled": return "tray.full.fill"
        default: return "mappin.circle.fill"
        }
    }

    private func locationColor(_ type: String) -> Color {
        switch type {
        case "warehouse": return .blue
        case "truck": return .green
        case "trailer": return .orange
        case "job": return .purple
        case "staging", "pulled": return .yellow
        default: return .gray
        }
    }

    private func locationTypeLabel(_ type: String) -> String {
        switch type {
        case "warehouse": return "Warehouse"
        case "truck": return "Truck"
        case "trailer": return "Trailer"
        case "job": return "Job"
        case "staging": return "Staged"
        case "pulled": return "Pulled"
        default: return type.capitalized
        }
    }
}

// MARK: - Supporting Types

private struct LocationTypeSection: Identifiable {
    let locationType: String
    let groups: [LocationGroup]
    let totalQty: Int
    var id: String { locationType }
}

struct LocationGroup: Identifiable {
    let locationType: String
    let locationId: Int64
    let items: [WarehouseService.LocationStock]
    let totalQty: Int
    var id: String { "\(locationType)-\(locationId)" }
}

// MARK: - Location Detail Sheet

private struct LocationDetailSheet: View {
    let group: LocationGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Type", value: locationTypeLabel(group.locationType))
                    LabeledContent("ID", value: "#\(group.locationId)")
                    LabeledContent("Total Parts", value: "\(group.items.count)")
                    LabeledContent("Total Quantity", value: "\(group.totalQty)")
                }

                Section("Parts") {
                    ForEach(group.items, id: \.partId) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.partName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let code = item.partCode, !code.isEmpty {
                                    Text(code)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(item.qty)")
                                .font(.headline)
                                .foregroundStyle(item.qty > 0 ? .green : .red)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("\(locationTypeLabel(group.locationType)) #\(group.locationId)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func locationTypeLabel(_ type: String) -> String {
        switch type {
        case "warehouse": return "Warehouse"
        case "truck": return "Truck"
        case "trailer": return "Trailer"
        case "job": return "Job"
        case "staging": return "Staged"
        case "pulled": return "Pulled"
        default: return type.capitalized
        }
    }
}
