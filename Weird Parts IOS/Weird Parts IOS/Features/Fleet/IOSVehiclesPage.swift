import SwiftUI
import WiredPartCore

/// Vehicles list page for iOS.
///
/// Displays a searchable list of fleet vehicles with vehicle number, name,
/// type, status badge, and assigned user. Supports pull-to-refresh and
/// status-based filtering.
struct IOSVehiclesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var vehicles: [FleetService.VehicleListItem] = []
    @State private var allVehicles: [FleetService.VehicleListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case createVehicle
        case help
        var id: String {
            switch self {
            case .createVehicle: return "createVehicle"
            case .help: return "help"
            }
        }
    }

    private let statusOptions = ["all", "active", "inactive", "maintenance", "retired"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "fleet-vehicles")
            SkippedModuleHint(moduleId: "fleet")
            statusPicker
            vehicleList
        }
        .task { appCore.onboardingManager?.markCompleted("fleet-vehicles-view") }
        .navigationTitle("Vehicles")
        .searchable(text: $searchText, prompt: "Search vehicles...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadData() }
        }
        .onAppear {
            NotificationCenter.default.post(
                name: .vehiclesPageActive,
                object: nil,
                userInfo: [
                    "context": "Vehicles Page: \(vehicles.count) vehicles, filter: \(statusFilter)."
                ]
            )
            // Register AI filter (prompt 62S)
            appCore.aiFilterRegistry.register(
                pageId: "vehicles",
                filterName: "Vehicle Status",
                options: statusOptions,
                activate: { value in
                    statusFilter = value
                    loadData()
                }
            )
            appCore.aiFilterRegistry.applyPendingFilter(pageId: "vehicles")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .vehiclesPageInactive, object: nil)
            appCore.aiFilterRegistry.deregister(pageId: "vehicles")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .createVehicle
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add vehicle")
                .requiresPermission("manage_fleet")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createVehicle:
                IOSCreateVehicleSheet(onSaved: { loadData() })
            case .help:
                PageHelpSheet(
                    title: "Vehicles Help",
                    sections: [
                        ("Overview", "This page lists all vehicles in the fleet. Each row shows the vehicle number, name, make/model, type, status, assigned driver, and current odometer reading."),
                        ("Filtering", "Use the status pills at the top to filter by Active, Inactive, Maintenance, or Retired vehicles. Tap All to see everything. Use the search bar to find vehicles by name, number, make, model, or driver."),
                        ("Adding a Vehicle", "Tap the + button in the top-right corner to add a new vehicle. You need the manage_fleet permission to add vehicles."),
                        ("Vehicle Detail", "Tap any vehicle row to open its detail page with tabs for overview, parts, tools, assignments, maintenance, usage, and inspections."),
                        ("Tips", "Pull down to refresh the list. Status badges are color-coded: green for active, orange for maintenance, red for retired, and gray for inactive.")
                    ]
                )
            }
        }
    }

    // MARK: - Status Picker

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allVehicles.count }
        return allVehicles.filter { $0.status == status }.count
    }

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    SmartFilterCard(
                        title: status == "all" ? "All" : status.capitalized,
                        count: countForStatus(status),
                        isSelected: statusFilter == status
                    ) {
                        statusFilter = status
                        loadData()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Vehicle List

    @ViewBuilder
    private var vehicleList: some View {
        if isLoading {
            ProgressView("Loading vehicles...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredVehicles.isEmpty {
            EmptyStateView(
                icon: "car",
                title: "No Vehicles",
                message: searchText.isEmpty ? "Add your first vehicle to get started." : "No vehicles match your criteria.",
                actionLabel: searchText.isEmpty ? "Add Vehicle" : nil
            ) {
                activeSheet = .createVehicle
            }
        } else {
            List(filteredVehicles, id: \.id) { vehicle in
                NavigationLink(destination: IOSVehicleDetailPage(vehicleId: vehicle.id)) {
                    vehicleRow(vehicle)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredVehicles: [FleetService.VehicleListItem] {
        guard !searchText.isEmpty else { return vehicles }
        let query = searchText.lowercased()
        return vehicles.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.vehicleNumber.lowercased().contains(query) ||
            ($0.make?.lowercased().contains(query) ?? false) ||
            ($0.model?.lowercased().contains(query) ?? false) ||
            ($0.assignedUserName?.lowercased().contains(query) ?? false)
        }
    }

    private func vehicleRow(_ vehicle: FleetService.VehicleListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vehicleIcon(vehicle.vehicleType))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vehicle.vehicleNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    typeBadge(vehicle.vehicleType)
                }
                Text(vehicle.vehicleName)
                    .fontWeight(.medium)
                if let make = vehicle.make, let model = vehicle.model {
                    HStack(spacing: 4) {
                        Text("\(make) \(model)")
                        if let year = vehicle.year {
                            Text("(\(String(year)))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(vehicle.status)
                if let user = vehicle.assignedUserName {
                    Label(user, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let odo = vehicle.currentOdometer {
                    Text("\(odo.formatted()) mi")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vehicle.vehicleName), \(vehicle.vehicleNumber), \(vehicle.vehicleType), status \(vehicle.status)")
    }

    // MARK: - Helpers

    private func vehicleIcon(_ type: String) -> String {
        switch type {
        case "truck": return "truck.box"
        case "van": return "bus"
        case "car": return "car"
        case "trailer": return "shippingbox"
        default: return "car"
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "inactive": .secondary
        case "maintenance": .orange
        case "retired": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.capitalized)
            .font(.caption2)
            .foregroundStyle(.blue)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = vehicles.isEmpty
        loadError = nil
        do {
            allVehicles = try service.listVehicles(status: nil)
            vehicles = statusFilter == "all"
                ? allVehicles
                : allVehicles.filter { $0.status == statusFilter }
        } catch {
            loadError = userFriendlyError(error, context: "load vehicles")
        }
        isLoading = false
    }
}
