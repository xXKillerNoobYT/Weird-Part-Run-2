import SwiftUI
import WiredPartCore

/// Inventory by location — shows all stock grouped by location type and ID.
///
/// Presents sections for each location type (Warehouse, Trucks, Trailers,
/// Jobs, Staged/Pulled). Each section lists parts with their quantities.
/// Supports search across all locations and pull-to-refresh.
/// Detail sheet includes action buttons: Transfer, Start Audit, View Grid.
struct WarehouseLocationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var locationStock: [WarehouseService.LocationStock] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var selectedLocation: LocationGroup?
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading locations...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if groupedLocations.isEmpty {
                emptyState
            } else {
                locationsList
            }
        }
        .searchable(text: $searchText, prompt: "Search parts across all locations...")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            PageHelpSheet(
                title: "Locations Help",
                sections: [
                    ("Overview", "View all stock organized by physical location: warehouses, trucks, trailers, job sites, and staging areas."),
                    ("Browsing", "Tap a location section to expand it and see all parts stored there. Search across all locations at once."),
                    ("Details", "Tap a specific location for detailed actions including transfers, audits, and inventory grid views.")
                ]
            )
        }
        .refreshable { loadData() }
        .sheet(item: $selectedLocation) { group in
            LocationDetailSheet(group: group)
                .environmentObject(appCore)
        }
        .background(DS.Background.page)
        .task { loadData() }
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
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func locationGroupRow(_ group: LocationGroup) -> some View {
        HStack(spacing: 12) {
            VStack {
                Image(systemName: locationIcon(group.locationType))
                    .font(.title3)
                    .foregroundStyle(locationColor(group.locationType))
            }
            .frame(width: 40, height: 40)
            .background(locationColor(group.locationType).opacity(0.12))
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
        if searchText.isEmpty {
            EmptyStateView(
                icon: "map.fill",
                title: "No Stock Found",
                message: "No stock at any location. Use the Movement Wizard to transfer parts to a location."
            )
        } else {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Results",
                message: "No parts match \"\(searchText)\" across any location."
            )
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            isLoading = false
            return
        }

        isLoading = locationStock.isEmpty
        loadError = nil

        do {
            locationStock = try service.getLocationStock()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func locationIcon(_ type: String) -> String {
        switch type {
        case "warehouse": "building.fill"
        case "truck": "truck.box.fill"
        case "trailer": "truck.box.badge.clock.fill"
        case "job": "hammer.fill"
        case "staging", "pulled": "tray.full.fill"
        default: "mappin.circle.fill"
        }
    }

    private func locationColor(_ type: String) -> Color {
        switch type {
        case "warehouse": .blue
        case "truck": .green
        case "trailer": .orange
        case "job": .purple
        case "staging", "pulled": .yellow
        default: .gray
        }
    }

    private func locationTypeLabel(_ type: String) -> String {
        switch type {
        case "warehouse": "Warehouse"
        case "truck": "Truck"
        case "trailer": "Trailer"
        case "job": "Job"
        case "staging": "Staged"
        case "pulled": "Pulled"
        default: type.capitalized
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
    @EnvironmentObject private var appCore: AppCore
    let group: LocationGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section {
                    LabeledContent("Type", value: locationTypeLabel(group.locationType))
                    LabeledContent("ID", value: "#\(group.locationId)")
                    LabeledContent("Total Parts", value: "\(group.items.count)")
                    LabeledContent("Total Quantity", value: "\(group.totalQty)")
                }

                // Action Buttons
                Section("Actions") {
                    Button {
                        dismiss()
                        // Post notification to open movement wizard with this location pre-selected
                        NotificationCenter.default.post(
                            name: .navigateToModule,
                            object: nil,
                            userInfo: [
                                "moduleId": "warehouse-movements",
                                "sourceLocationType": group.locationType,
                                "sourceLocationId": group.locationId
                            ]
                        )
                    } label: {
                        Label("Transfer From Here", systemImage: "arrow.left.arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                    }

                    Button {
                        dismiss()
                        NotificationCenter.default.post(
                            name: .navigateToModule,
                            object: nil,
                            userInfo: [
                                "moduleId": "warehouse-audit",
                                "locationType": group.locationType,
                                "locationId": group.locationId
                            ]
                        )
                    } label: {
                        Label("Start Audit", systemImage: "clipboard.fill")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        dismiss()
                        NotificationCenter.default.post(
                            name: .navigateToModule,
                            object: nil,
                            userInfo: [
                                "moduleId": "warehouse-inventory",
                                "locationType": group.locationType,
                                "locationId": group.locationId
                            ]
                        )
                    } label: {
                        Label("View in Inventory Grid", systemImage: "square.grid.3x3.fill")
                            .foregroundStyle(.purple)
                    }
                }

                // Parts List
                if group.items.isEmpty {
                    Section("Parts") {
                        VStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No stock at this location.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Use the Movement Wizard to transfer parts here.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
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
            }
            .navigationTitle("\(locationTypeLabel(group.locationType)) #\(group.locationId)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func locationTypeLabel(_ type: String) -> String {
        switch type {
        case "warehouse": "Warehouse"
        case "truck": "Truck"
        case "trailer": "Trailer"
        case "job": "Job"
        case "staging": "Staged"
        case "pulled": "Pulled"
        default: type.capitalized
        }
    }
}
