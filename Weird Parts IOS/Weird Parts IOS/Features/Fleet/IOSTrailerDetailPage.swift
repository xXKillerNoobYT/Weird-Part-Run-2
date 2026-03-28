import SwiftUI
import WiredPartCore

/// Trailer detail page — treats the trailer as a mini warehouse with storage units,
/// location-aware MIN/MAX levels, and location history tracking.
struct IOSTrailerDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let trailerId: Int64

    // MARK: - State

    @State private var trailer: FleetService.TrailerDetail?
    @State private var stock: [FleetService.TrailerStockItem] = []
    @State private var storageUnits: [FleetService.TrailerStorageUnit] = []
    @State private var locationHistory: [FleetService.TrailerLocationRecord] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab: TrailerTab = .inventory
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    enum TrailerTab: String, CaseIterable {
        case inventory = "Inventory"
        case tools = "Tools"
        case storage = "Storage"
        case history = "History"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading trailer...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let trailer {
                trailerContent(trailer)
            } else {
                EmptyStateView(
                    icon: "truck.box.fill",
                    title: "Trailer Not Found",
                    message: "This trailer could not be loaded."
                )
            }
        }
        .navigationTitle(trailer?.name ?? "Trailer")
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Trailer Detail Help",
                sections: [
                    ("Overview", "This page shows everything about a single trailer. The location badge at the top tells you whether the trailer is at the shop or in the field. Use the segmented tabs to switch between Inventory, Tools, Storage, and History."),
                    ("Location Rules", "When a trailer is in the field, MIN/MAX stock levels are enforced — items below MIN appear as warnings. When at the shop, MIN/MAX rules are relaxed since the warehouse is nearby for restocking."),
                    ("Inventory Tab", "Shows all parts loaded on the trailer with current quantities. In the field, progress bars show stock health against target levels. Red means below minimum, orange means between min and target, green means at or above target."),
                    ("Tools Tab", "Shows tools loaded on the trailer, tracked through stock templates."),
                    ("Storage Tab", "Shows the physical storage units on the trailer (shelves, drawers, compartments, bins) and which parts are in each unit. Items not assigned to a storage unit appear under Unassigned."),
                    ("History Tab", "Shows the trailer's location history — where it has been, when it arrived and departed, and who recorded the movement. Location types include shop, job site, and in transit."),
                    ("Tips", "Pull down to refresh all data. If stock levels look wrong, check whether the trailer's location is set correctly — MIN/MAX enforcement depends on whether the trailer is at the shop or in the field.")
                ]
            )
        }
    }

    // MARK: - Content

    private func trailerContent(_ trailer: FleetService.TrailerDetail) -> some View {
        VStack(spacing: 0) {
            // Location badge bar
            HStack {
                Image(systemName: trailer.isAtShop ? "building.2.fill" : "map.fill")
                    .foregroundStyle(trailer.isAtShop ? .green : .blue)
                Text(trailer.isAtShop ? "At Shop" : "In Field")
                    .font(.caption).fontWeight(.medium)
                Spacer()
                if !trailer.isAtShop {
                    Text("MIN/MAX enforced")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("MIN/MAX relaxed")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(TrailerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Tab content
            List {
                switch selectedTab {
                case .inventory:
                    inventorySection(trailer)
                case .tools:
                    toolsSection
                case .storage:
                    storageSection
                case .history:
                    locationHistorySection
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Inventory Tab

    @ViewBuilder
    private func inventorySection(_ trailer: FleetService.TrailerDetail) -> some View {
        // Summary alert for items below MIN (only when away from shop)
        Section {
            if !trailer.isAtShop {
                let belowMin = stock.filter { item in
                    guard let min = item.minQty else { return false }
                    return item.quantity < min
                }
                if !belowMin.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(belowMin.count) item\(belowMin.count == 1 ? "" : "s") below MIN")
                            .font(.subheadline)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All stock levels OK")
                            .font(.subheadline)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("At shop — restock as needed")
                        .font(.subheadline)
                }
            }
        }

        // Stock list
        Section("Parts") {
            if stock.isEmpty {
                Text("No inventory items").foregroundStyle(.secondary)
            } else {
                ForEach(stock) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.partName).font(.subheadline)
                            if let unitName = item.storageUnitName {
                                Text(unitName).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.quantity)")
                                .font(.subheadline).monospacedDigit()

                            // Show MIN/TARGET/MAX health bars only when away from shop
                            if !trailer.isAtShop {
                                if let minVal = item.minQty, let target = item.targetQty, target > 0 {
                                    ProgressView(
                                        value: Swift.min(Double(item.quantity), Double(target)),
                                        total: Double(target)
                                    )
                                    .tint(
                                        item.quantity < minVal ? .red :
                                        item.quantity >= target ? .green : .orange
                                    )
                                    .frame(width: 50)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tools Tab

    @ViewBuilder
    private var toolsSection: some View {
        Section("Tools on Trailer") {
            // Tools loaded on the trailer are tracked via the template lines
            Text("Tool tracking available via stock templates")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Storage Tab

    @ViewBuilder
    private var storageSection: some View {
        if storageUnits.isEmpty {
            Section {
                Text("No storage units configured")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(storageUnits) { unit in
                let unitStock = stock.filter { $0.storageUnitId == unit.id }
                Section {
                    if unitStock.isEmpty {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(unitStock) { item in
                            HStack {
                                Text(item.partName).font(.subheadline)
                                Spacer()
                                Text("×\(item.quantity)")
                                    .font(.caption).monospacedDigit()
                            }
                        }
                    }
                    Text("\(unitStock.count)/\(unit.capacitySlots ?? 0) slots used")
                        .font(.caption2).foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Image(systemName: storageIcon(unit.unitType))
                        Text(unit.name)
                    }
                }
            }

            // Items not assigned to any storage unit
            let unassigned = stock.filter { $0.storageUnitId == nil }
            if !unassigned.isEmpty {
                Section("Unassigned") {
                    ForEach(unassigned) { item in
                        HStack {
                            Text(item.partName).font(.subheadline)
                            Spacer()
                            Text("×\(item.quantity)")
                                .font(.caption).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Location History Tab

    @ViewBuilder
    private var locationHistorySection: some View {
        Section("Location History") {
            if locationHistory.isEmpty {
                Text("No location history").foregroundStyle(.secondary)
            } else {
                ForEach(locationHistory) { record in
                    HStack {
                        Image(systemName: locationIcon(record.locationType))
                            .foregroundStyle(locationColor(record.locationType))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.locationLabel ?? record.locationType.capitalized)
                                .font(.subheadline)
                            HStack(spacing: 4) {
                                Text(String(record.arrivedAt.prefix(16)))
                                if let departed = record.departedAt {
                                    Text("→")
                                    Text(String(departed.prefix(16)))
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if let by = record.recordedByName {
                                Text("By: \(by)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func storageIcon(_ unitType: String) -> String {
        switch unitType {
        case "shelf": return "square.stack.3d.up"
        case "drawer": return "tray.fill"
        case "compartment": return "rectangle.split.3x1"
        case "bin": return "archivebox.fill"
        default: return "shippingbox.fill"
        }
    }

    private func locationIcon(_ locationType: String) -> String {
        switch locationType {
        case "shop": return "building.2.fill"
        case "job_site": return "mappin.circle.fill"
        case "in_transit": return "truck.box.fill"
        default: return "location.fill"
        }
    }

    private func locationColor(_ locationType: String) -> Color {
        switch locationType {
        case "shop": return .green
        case "job_site": return .blue
        case "in_transit": return .orange
        default: return .secondary
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let fleet = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = trailer == nil
        loadError = nil

        do {
            trailer = try fleet.getTrailerDetail(trailerId: trailerId)
            if trailer != nil {
                stock = try fleet.getTrailerStock(trailerId: trailerId)
                storageUnits = try fleet.getTrailerStorageUnits(trailerId: trailerId)
                locationHistory = try fleet.getTrailerLocationHistory(trailerId: trailerId)
            }
        } catch {
            loadError = userFriendlyError(error, context: "load trailer details")
        }
        isLoading = false
    }
}
