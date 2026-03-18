import SwiftUI
import WiredPartCore

/// Driver's personal vehicle dashboard — "My Truck" page.
///
/// Shows the vehicle currently assigned to the logged-in user with key info,
/// upcoming maintenance, recent mileage, and quick action buttons.
struct IOSMyTruckPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var vehicle: FleetService.VehicleDetail?
    @State private var recentMileage: [FleetService.MileageRow] = []
    @State private var recentFuel: [FleetService.FuelRow] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading your vehicle...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let vehicle {
                vehicleContent(vehicle)
            } else {
                noVehicleView
            }
        }
        .navigationTitle("My Truck")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - No Vehicle

    private var noVehicleView: some View {
        EmptyStateView(
            icon: "car.fill",
            title: "No Vehicle Assigned",
            message: "You don't currently have a vehicle assigned to you. Contact your supervisor to get assigned."
        )
    }

    // MARK: - Vehicle Content

    private func vehicleContent(_ v: FleetService.VehicleDetail) -> some View {
        List {
            vehicleHeaderSection(v)
            quickActionsSection
            assignmentsSection(v)
            mileageSection
            fuelSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func vehicleHeaderSection(_ v: FleetService.VehicleDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "car.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.vehicleName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(v.vehicleNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    Spacer()
                    StatusBadge(text: v.status.capitalized, color: statusColor(v.status))
                }

                if let make = v.make, let model = v.model {
                    HStack(spacing: 4) {
                        Text("\(make) \(model)")
                        if let year = v.year { Text("(\(String(year)))") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let odo = v.currentOdometer {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundStyle(.secondary)
                        Text("\(odo.formatted()) miles")
                            .font(.subheadline)
                    }
                }

                if let plate = v.licensePlate, !plate.isEmpty {
                    HStack {
                        Image(systemName: "car.window.right")
                            .foregroundStyle(.secondary)
                        Text("Plate: \(plate)")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @State private var showLogMileage = false
    @State private var showLogFuel = false
    @State private var showReportIssue = false

    private var quickActionsSection: some View {
        Section("Quick Actions") {
            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "fleet", "tabId": "fleet-mileage"]
                )
            } label: {
                Label("Log Mileage", systemImage: "speedometer")
            }
            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "fleet", "tabId": "fleet-fuel"]
                )
            } label: {
                Label("Log Fuel", systemImage: "fuelpump.fill")
            }
            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "fleet", "tabId": "fleet-maintenance"]
                )
            } label: {
                Label("Report Issue", systemImage: "exclamationmark.triangle.fill")
            }
            Button {
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "fleet", "tabId": "fleet-inspections"]
                )
            } label: {
                Label("Pre-Trip Inspection", systemImage: "checklist")
            }
        }
    }

    private func assignmentsSection(_ v: FleetService.VehicleDetail) -> some View {
        Section("Assignments") {
            if v.assignments.isEmpty {
                Text("No active assignments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(v.assignments) { assignment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignment.userName)
                                .fontWeight(.medium)
                            Text(assignment.assignmentType.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if assignment.isTakeHome {
                            Label("Take Home", systemImage: "house.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private var mileageSection: some View {
        Section("Recent Mileage") {
            if recentMileage.isEmpty {
                Text("No recent mileage logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentMileage) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(log.logDate.prefix(10)))
                                .font(.subheadline)
                            if let purpose = log.purpose, !purpose.isEmpty {
                                Text(purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let miles = log.totalMiles {
                            Text(String(format: "%.1f mi", miles))
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }

    private var fuelSection: some View {
        Section("Recent Fuel") {
            if recentFuel.isEmpty {
                Text("No recent fuel logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentFuel) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(log.logDate.prefix(10)))
                                .font(.subheadline)
                            if let station = log.station, !station.isEmpty {
                                Text(station)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let gal = log.gallons {
                                Text(String(format: "%.1f gal", gal))
                                    .fontWeight(.medium)
                            }
                            if let cost = log.totalCost {
                                Text(String(format: "$%.2f", cost))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return .green
        case "maintenance": return .orange
        case "inactive": return .secondary
        case "retired": return .red
        default: return .secondary
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let fleet = appCore.fleetService else { return }
        isLoading = vehicle == nil
        loadError = nil

        do {
            // Find current user's assigned vehicle by user ID
            guard let currentUserId = appCore.currentUser?.id else {
                vehicle = nil
                isLoading = false
                return
            }
            let vehicles = try fleet.listVehicles(status: "active")

            // Find first vehicle assigned to the current user by ID
            if let assigned = vehicles.first(where: { $0.assignedUserId == currentUserId }) {
                vehicle = try fleet.getVehicleDetail(id: assigned.id)

                // Load recent logs for this vehicle
                recentMileage = try fleet.listMileageLogs(vehicleId: assigned.id, limit: 5)
                recentFuel = try fleet.listFuelLogs(vehicleId: assigned.id, limit: 5)
            } else {
                vehicle = nil
                recentMileage = []
                recentFuel = []
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
