import SwiftUI
import WiredPartCore

/// Tabbed vehicle detail page showing all vehicle information.
///
/// Tabs: Overview, Assignments, Maintenance, Mileage, Fuel
struct IOSVehicleDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let vehicleId: Int64

    @State private var vehicle: FleetService.VehicleDetail?
    @State private var maintenance: [FleetService.MaintenanceRow] = []
    @State private var mileage: [FleetService.MileageRow] = []
    @State private var fuel: [FleetService.FuelRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab = "overview"
    @State private var showAssignDriver = false

    private let tabs = ["overview", "assignments", "maintenance", "mileage", "fuel"]

    var body: some View {
        VStack(spacing: 0) {
            tabPicker

            if isLoading {
                ProgressView("Loading vehicle...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let v = vehicle {
                tabContent(v)
            }
        }
        .navigationTitle(vehicle?.vehicleName ?? "Vehicle Detail")
        .refreshable { loadData() }
        .task { loadData() }
        .sheet(isPresented: $showAssignDriver) {
            IOSAssignDriverSheet(vehicleId: vehicleId)
        }
        .onChange(of: showAssignDriver) { _, isShowing in
            if !isShowing { loadData() }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.capitalized)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTab == tab ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ v: FleetService.VehicleDetail) -> some View {
        switch selectedTab {
        case "overview":
            overviewTab(v)
        case "assignments":
            assignmentsTab(v)
        case "maintenance":
            maintenanceTab
        case "mileage":
            mileageTab
        case "fuel":
            fuelTab
        default:
            Text("Unknown tab")
        }
    }

    // MARK: - Overview

    private func overviewTab(_ v: FleetService.VehicleDetail) -> some View {
        List {
            Section("Vehicle Info") {
                detailRow("Number", v.vehicleNumber)
                detailRow("Name", v.vehicleName)
                detailRow("Type", v.vehicleType.capitalized)
                detailRow("Status", v.status.capitalized)
                if let make = v.make { detailRow("Make", make) }
                if let model = v.model { detailRow("Model", model) }
                if let year = v.year { detailRow("Year", String(year)) }
                if let color = v.color { detailRow("Color", color) }
            }

            Section("Registration") {
                if let vin = v.vin, !vin.isEmpty { detailRow("VIN", vin) }
                if let plate = v.licensePlate, !plate.isEmpty { detailRow("Plate", plate) }
                if let policy = v.insurancePolicy { detailRow("Insurance", policy) }
                if let expiry = v.insuranceExpiry { detailRow("Ins. Expiry", String(expiry.prefix(10))) }
                if let regExp = v.registrationExpiry { detailRow("Reg. Expiry", String(regExp.prefix(10))) }
            }

            if let odo = v.currentOdometer {
                Section("Odometer") {
                    detailRow("Current", "\(odo.formatted()) miles")
                }
            }

            if let notes = v.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.subheadline)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Assignments

    private func assignmentsTab(_ v: FleetService.VehicleDetail) -> some View {
        List {
            Section {
                Button {
                    showAssignDriver = true
                } label: {
                    Label("Assign Driver", systemImage: "person.badge.plus")
                }
                .requiresPermission("manage_fleet")
            }

            if v.assignments.isEmpty {
                Section {
                    Text("No assignments")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Active Assignments") {
                    ForEach(v.assignments.filter(\.isActive)) { a in
                        assignmentRow(a)
                    }
                }

                let inactive = v.assignments.filter { !$0.isActive }
                if !inactive.isEmpty {
                    Section("Past Assignments") {
                        ForEach(inactive) { a in
                            assignmentRow(a)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func assignmentRow(_ a: FleetService.AssignmentRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.userName)
                    .fontWeight(.medium)
                Text("\(a.assignmentType.capitalized) — since \(String(a.startDate.prefix(10)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if a.isTakeHome {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Circle()
                .fill(a.isActive ? .green : .secondary)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Maintenance

    private var maintenanceTab: some View {
        List {
            if maintenance.isEmpty {
                Text("No maintenance records")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(maintenance) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.maintenanceTypeName ?? "Service")
                                .fontWeight(.medium)
                            Text(String(record.performedAt.prefix(10)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let by = record.performedByName {
                                Text("By: \(by)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let cost = record.cost {
                                Text(String(format: "$%.2f", cost))
                                    .fontWeight(.medium)
                            }
                            if let odo = record.odometerReading {
                                Text("\(odo.formatted()) mi")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Mileage

    private var mileageTab: some View {
        List {
            if mileage.isEmpty {
                Text("No mileage logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mileage) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(log.logDate.prefix(10)))
                                .fontWeight(.medium)
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Fuel

    private var fuelTab: some View {
        List {
            if fuel.isEmpty {
                Text("No fuel logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fuel) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(log.logDate.prefix(10)))
                                .fontWeight(.medium)
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let fleet = appCore.fleetService else { return }
        isLoading = vehicle == nil
        loadError = nil
        do {
            vehicle = try fleet.getVehicleDetail(id: vehicleId)
            maintenance = try fleet.listMaintenanceRecords(vehicleId: vehicleId, limit: 20)
            mileage = try fleet.listMileageLogs(vehicleId: vehicleId, limit: 20)
            fuel = try fleet.listFuelLogs(vehicleId: vehicleId, limit: 20)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
