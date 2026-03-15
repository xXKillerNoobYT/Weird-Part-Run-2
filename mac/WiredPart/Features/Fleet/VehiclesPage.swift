import SwiftUI
import WiredPartCore

/// Vehicles list page.
///
/// Displays a searchable, sortable table of all vehicles with number, name,
/// type, status, make/model, odometer, and assigned user columns. Supports
/// filtering by status and searching by vehicle name or number.
struct VehiclesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var vehicles: [FleetService.VehicleListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\FleetService.VehicleListItem.vehicleNumber)]

    private let statusOptions = ["all", "active", "inactive", "maintenance", "decommissioned"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vehicles")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(vehicles.count) vehicle\(vehicles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { load() }

            TextField("Search vehicles...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading vehicles...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vehicles.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "truck.box")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No vehicles found")
                    .font(.headline)
                Text("Add a vehicle to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedVehicles, sortOrder: $sortOrder) {
                TableColumn("Number", value: \.vehicleNumber) { vehicle in
                    Text(vehicle.vehicleNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Name", value: \.vehicleName) { vehicle in
                    Text(vehicle.vehicleName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Type", value: \.vehicleType) { vehicle in
                    Text(vehicle.vehicleType.capitalized)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Status", value: \.status) { vehicle in
                    statusBadge(vehicle.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Make/Model") { (vehicle: FleetService.VehicleListItem) in
                    Text(makeModelString(vehicle))
                }
                .width(min: 100, ideal: 150)

                TableColumn("Odometer") { (vehicle: FleetService.VehicleListItem) in
                    if let odo = vehicle.currentOdometer {
                        Text("\(odo.formatted()) mi")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 100)

                TableColumn("Assigned To") { (vehicle: FleetService.VehicleListItem) in
                    Text(vehicle.assignedUserName ?? "-")
                        .foregroundStyle(vehicle.assignedUserName != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedVehicles: [FleetService.VehicleListItem] {
        vehicles.sorted(using: sortOrder)
    }

    // MARK: - Helpers

    private func makeModelString(_ vehicle: FleetService.VehicleListItem) -> String {
        let parts = [vehicle.make, vehicle.model].compactMap { $0 }
        if parts.isEmpty { return "-" }
        if let year = vehicle.year {
            return "\(year) \(parts.joined(separator: " "))"
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "inactive": .secondary
        case "maintenance": .orange
        case "decommissioned": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = FleetService(db: db)
        isLoading = true
        do {
            let allVehicles = try service.listVehicles(
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Client-side search filter
            if searchText.isEmpty {
                vehicles = allVehicles
            } else {
                let query = searchText.lowercased()
                vehicles = allVehicles.filter {
                    $0.vehicleNumber.lowercased().contains(query) ||
                    $0.vehicleName.lowercased().contains(query) ||
                    ($0.make?.lowercased().contains(query) ?? false) ||
                    ($0.model?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[VehiclesPage] Load error: \(error)")
        }
        isLoading = false
    }
}
