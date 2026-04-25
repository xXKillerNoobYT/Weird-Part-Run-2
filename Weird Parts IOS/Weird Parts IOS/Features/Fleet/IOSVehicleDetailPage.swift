import SwiftUI
import WiredPartCore

/// Tabbed vehicle detail page showing all vehicle information.
///
/// Tabs: Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections
struct IOSVehicleDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let vehicleId: Int64

    // MARK: - State

    @State private var vehicle: FleetService.VehicleDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab: VehicleTab = .overview

    private enum ActiveSheet: Identifiable {
        case assignDriver
        case inspection
        case help
        var id: String {
            switch self {
            case .assignDriver: return "assignDriver"
            case .inspection: return "inspection"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    // Tab-specific data (loaded lazily)
    @State private var truckStock: [FleetService.VehicleStockItem] = []
    @State private var transferParts: [FleetService.VehicleStockItem] = []
    @State private var vehicleTools: [FleetService.VehicleToolItem] = []
    @State private var maintenance: [FleetService.MaintenanceRow] = []
    @State private var mileage: [FleetService.MileageRow] = []
    @State private var fuel: [FleetService.FuelRow] = []
    @State private var inspectionRecords: [FleetService.InspectionRecordRow] = []

    // Track which tabs have been loaded
    @State private var loadedTabs: Set<VehicleTab> = []
    @State private var tabLoadError: String?

    enum VehicleTab: String, CaseIterable {
        case overview = "Overview"
        case parts = "Parts"
        case tools = "Tools"
        case assignments = "Assignments"
        case maintenance = "Maintenance"
        case usage = "Usage"
        case inspections = "Inspections"
    }

    // MARK: - Body

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .assignDriver:
                IOSAssignDriverSheet(vehicleId: vehicleId)
            case .inspection:
                PreTripInspectionView(
                    vehicleId: vehicleId,
                    vehicleType: vehicle?.vehicleType ?? "truck"
                ) { _ in
                    // Reload inspections data after completion
                    loadedTabs.remove(.inspections)
                    loadTabDataIfNeeded(.inspections)
                }
            case .help:
                PageHelpSheet(
                    title: "Vehicle Detail Help",
                    sections: [
                        ("Overview", "This page shows everything about a single vehicle. Use the tabs at the top to switch between Overview, Parts, Tools, Assignments, Maintenance, Usage, and Inspections."),
                        ("Overview Tab", "Shows vehicle info (number, name, type, make/model, year, color), registration details (VIN, plate, insurance, expiry dates), current odometer, and assigned driver."),
                        ("Parts Tab", "Shows spare parts loaded on this truck (truck stock) with quantity vs. target levels, plus any transfer items in transit to or from this vehicle."),
                        ("Tools Tab", "Lists all tools currently checked out to this vehicle with condition status and who checked them out."),
                        ("Assignments Tab", "Shows current and past driver assignments. Tap Assign Driver to assign a new driver. Take-home vehicles are marked with a house icon."),
                        ("Maintenance Tab", "Lists maintenance service records for this vehicle including type, date, cost, technician, and odometer at time of service."),
                        ("Usage Tab", "Combined view of fuel fill-ups and mileage logs. Shows the 10 most recent entries for each."),
                        ("Inspections Tab", "Tap Start Pre-Trip Inspection to begin a new checklist. Below that you can see the history of past inspections with pass/fail/conditional results."),
                        ("Tips", "Pull down on any tab to refresh data. Each tab loads its data independently so switching tabs is fast after the first load.")
                    ]
                )
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            if newValue == nil { loadData() }
        }
        .onChange(of: selectedTab) { _, newTab in
            loadTabDataIfNeeded(newTab)
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VehicleTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
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
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ v: FleetService.VehicleDetail) -> some View {
        List {
            if let error = tabLoadError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            switch selectedTab {
            case .overview:
                overviewTab(v)
            case .parts:
                partsTab
            case .tools:
                toolsTab
            case .assignments:
                assignmentsTab(v)
            case .maintenance:
                maintenanceTab
            case .usage:
                usageTab
            case .inspections:
                inspectionsTab
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private func overviewTab(_ v: FleetService.VehicleDetail) -> some View {
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

        Section("Quick Stats") {
            if let odo = v.currentOdometer {
                detailRow("Odometer", "\(odo.formatted()) miles")
            }
            // Current driver
            let activeAssignment = v.assignments.first(where: \.isActive)
            if let driver = activeAssignment {
                detailRow("Current Driver", driver.userName)
            } else {
                detailRow("Current Driver", "Unassigned")
            }
        }

        if let notes = v.notes, !notes.isEmpty {
            Section("Notes") {
                Text(notes)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Parts Tab

    @ViewBuilder
    private var partsTab: some View {
        Section("Spare Parts (Truck Stock)") {
            if truckStock.isEmpty {
                Text("No spare parts loaded").foregroundStyle(.secondary)
            } else {
                ForEach(truckStock) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.partName).font(.subheadline)
                            Text("Qty: \(part.quantity) / Target: \(part.targetQty ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let target = part.targetQty, target > 0 {
                            ProgressView(
                                value: min(Double(part.quantity), Double(target)),
                                total: Double(target)
                            )
                            .tint(healthColor(current: part.quantity, min: part.minQty, target: target))
                            .frame(width: 60)
                        }
                    }
                }
            }
        }

        Section("Transfer Area") {
            if transferParts.isEmpty {
                Text("No items in transit").foregroundStyle(.secondary)
            } else {
                ForEach(transferParts) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.partName).font(.subheadline)
                            HStack(spacing: 4) {
                                Text(part.sourceLocation ?? "?")
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                Text(part.destinationLocation ?? "?")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("×\(part.quantity)")
                            .font(.subheadline).monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Tools Tab

    @ViewBuilder
    private var toolsTab: some View {
        Section("Checked-Out Tools") {
            if vehicleTools.isEmpty {
                Text("No tools on this vehicle").foregroundStyle(.secondary)
            } else {
                ForEach(vehicleTools) { tool in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.toolName).font(.subheadline)
                            Text("Checked out by \(tool.checkedOutBy)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tool.condition.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(conditionColor(tool.condition).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Assignments Tab

    @ViewBuilder
    private func assignmentsTab(_ v: FleetService.VehicleDetail) -> some View {
        Section {
            Button {
                activeSheet = .assignDriver
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
            let active = v.assignments.filter(\.isActive)
            if !active.isEmpty {
                Section("Active Assignments") {
                    ForEach(active) { a in
                        assignmentRow(a)
                    }
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

    private func assignmentRow(_ a: FleetService.AssignmentRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.userName)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(a.assignmentType.capitalized)
                    Text("—")
                    Text("since \(String(a.startDate.prefix(10)))")
                    if let end = a.endDate {
                        Text("to \(String(end.prefix(10)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if a.isTakeHome {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Status: Take-home vehicle")
            }
            if a.isActive {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Maintenance Tab

    @ViewBuilder
    private var maintenanceTab: some View {
        Section("Maintenance Records") {
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
    }

    // MARK: - Usage Tab (Combined Fuel + Mileage)

    @ViewBuilder
    private var usageTab: some View {
        Section("Fuel History") {
            if fuel.isEmpty {
                Text("No fuel logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fuel.prefix(10), id: \.id) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let gal = log.gallons {
                                Text(String(format: "%.1f gal", gal))
                                    .font(.subheadline)
                            }
                            Text(String(log.logDate.prefix(10)))
                                .font(.caption).foregroundStyle(.secondary)
                            if let station = log.station, !station.isEmpty {
                                Text(station)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let cost = log.totalCost {
                            Text(String(format: "$%.2f", cost))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        Section("Mileage") {
            if mileage.isEmpty {
                Text("No mileage logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mileage.prefix(10), id: \.id) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let miles = log.totalMiles {
                                Text(String(format: "%.1f mi", miles))
                                    .font(.subheadline)
                            }
                            if let purpose = log.purpose, !purpose.isEmpty {
                                Text(purpose)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(log.logDate.prefix(10)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Inspections Tab

    @ViewBuilder
    private var inspectionsTab: some View {
        Section {
            Button {
                activeSheet = .inspection
            } label: {
                Label("Start Pre-Trip Inspection", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }

        Section("Inspection History") {
            if inspectionRecords.isEmpty {
                Text("No inspections recorded").foregroundStyle(.secondary)
            } else {
                ForEach(inspectionRecords) { record in
                    HStack {
                        Image(systemName: inspectionIcon(record.result))
                            .foregroundStyle(inspectionColor(record.result))
                            .accessibilityLabel("Status: \(record.result.capitalized)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.inspectorName).font(.subheadline)
                            Text(String(record.performedAt.prefix(10)))
                                .font(.caption).foregroundStyle(.secondary)
                            if let odo = record.odometerReading {
                                Text("\(odo.formatted()) mi")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let notes = record.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(record.result.capitalized)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(inspectionColor(record.result).opacity(0.15))
                            .foregroundStyle(inspectionColor(record.result))
                            .clipShape(Capsule())
                    }
                }
            }
        }
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

    private func healthColor(current: Int, min: Int?, target: Int) -> Color {
        if current < (min ?? 0) { return .red }
        if current >= target { return .green }
        return .orange
    }

    private func conditionColor(_ condition: String) -> Color {
        switch condition.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "poor": return .red
        case "damaged": return .red
        default: return .secondary
        }
    }

    private func inspectionIcon(_ result: String) -> String {
        switch result.lowercased() {
        case "pass": return "checkmark.circle.fill"
        case "fail": return "xmark.circle.fill"
        case "conditional": return "exclamationmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private func inspectionColor(_ result: String) -> Color {
        switch result.lowercased() {
        case "pass": return .green
        case "fail": return .red
        case "conditional": return .orange
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
        isLoading = vehicle == nil
        loadError = nil
        do {
            vehicle = try fleet.getVehicleDetail(id: vehicleId)
            // Reset tab loading tracking so tabs reload on refresh
            loadedTabs = [.overview, .assignments] // overview + assignments use vehicle data directly
            tabLoadError = nil
            // Load current tab data
            loadTabDataIfNeeded(selectedTab)
        } catch {
            loadError = userFriendlyError(error, context: "load vehicle details")
        }
        isLoading = false
    }

    private func loadTabDataIfNeeded(_ tab: VehicleTab) {
        // Overview and assignments use vehicle data directly
        guard tab != .overview && tab != .assignments else { return }
        guard !loadedTabs.contains(tab) else { return }
        guard let fleet = appCore.fleetService else {
            tabLoadError = "Service not available"
            return
        }

        tabLoadError = nil
        do {
            switch tab {
            case .parts:
                truckStock = try fleet.getVehicleStock(vehicleId: vehicleId, stockType: "truck_stock")
                transferParts = try fleet.getVehicleStock(vehicleId: vehicleId, stockType: "transfer")
            case .tools:
                vehicleTools = try fleet.getVehicleTools(vehicleId: vehicleId)
            case .maintenance:
                maintenance = try fleet.listMaintenanceRecords(vehicleId: vehicleId, limit: 20)
            case .usage:
                fuel = try fleet.listFuelLogs(vehicleId: vehicleId, limit: 20)
                mileage = try fleet.listMileageLogs(vehicleId: vehicleId, limit: 20)
            case .inspections:
                inspectionRecords = try fleet.getInspectionRecords(vehicleId: vehicleId, limit: 20)
            default:
                break
            }
            loadedTabs.insert(tab)
        } catch {
            tabLoadError = userFriendlyError(error, context: "load vehicle details")
        }
    }
}
