import SwiftUI
import WiredPartCore

/// Driver's personal vehicle dashboard — "My Truck" page.
///
/// Shows the vehicle currently assigned to the logged-in user with smart card KPIs,
/// two inventory types (Truck Stock vs Transfer Area), quick actions,
/// and attached trailer section.
struct IOSMyTruckPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var vehicle: FleetService.VehicleDetail?
    @State private var vehicleStats: FleetService.MyVehicleStats?
    @State private var truckStock: [FleetService.VehicleStockItem] = []
    @State private var transferItems: [FleetService.VehicleStockItem] = []
    @State private var recentMileage: [FleetService.MileageRow] = []
    @State private var recentFuel: [FleetService.FuelRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var inventoryTab: InventoryTab = .truckStock
    @State private var activeSheet: ActiveSheet?

    enum InventoryTab: String, CaseIterable {
        case truckStock = "Truck Stock"
        case transfer = "Transfer"
    }

    enum ActiveSheet: Identifiable {
        case logFuel
        case reportIssue
        case addTransferItem
        case help

        var id: String {
            switch self {
            case .logFuel: return "logFuel"
            case .reportIssue: return "reportIssue"
            case .addTransferItem: return "addTransferItem"
            case .help: return "help"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "fleet-my-truck")

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
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("fleet-my-truck")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
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
            smartCardsSection
            quickActionsSection
            inventorySection
            trailerSection
            mileageSection
            fuelSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Header

    private func vehicleHeaderSection(_ v: FleetService.VehicleDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "car.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
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
                            .accessibilityHidden(true)
                        Text("\(odo.formatted()) miles")
                            .font(.subheadline)
                    }
                }

                if let plate = v.licensePlate, !plate.isEmpty {
                    HStack {
                        Image(systemName: "car.window.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Plate: \(plate)")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Smart Cards

    private var smartCardsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    MyVehicleSmartCard(
                        title: "Tools",
                        value: "\(vehicleStats?.toolCount ?? 0)",
                        icon: "wrench.fill",
                        color: .blue
                    )
                    MyVehicleSmartCard(
                        title: "Parts",
                        value: "\(vehicleStats?.partCount ?? 0)",
                        icon: "shippingbox.fill",
                        color: .green
                    )

                    if let fuel = vehicleStats?.fuelLevel {
                        MyVehicleSmartCard(
                            title: "Tank",
                            value: "\(Int(fuel * 100))%",
                            icon: "fuelpump.fill",
                            color: fuel < 0.25 ? .red : fuel < 0.5 ? .orange : .green
                        )
                    }

                    MyVehicleSmartCard(
                        title: "Maintenance",
                        value: "\(vehicleStats?.maintenanceDue ?? 0)",
                        icon: "wrench.and.screwdriver.fill",
                        color: (vehicleStats?.maintenanceDue ?? 0) > 0 ? .red : .green
                    )

                    if (vehicleStats?.transferItems ?? 0) > 0 {
                        MyVehicleSmartCard(
                            title: "Transfers",
                            value: "\(vehicleStats?.transferItems ?? 0)",
                            icon: "arrow.left.arrow.right",
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        Section("Quick Actions") {
            HStack(spacing: 12) {
                QuickActionBtn(title: "Log Fuel", icon: "fuelpump.fill", color: .blue) {
                    activeSheet = .logFuel
                }
                QuickActionBtn(title: "Report Issue", icon: "exclamationmark.triangle.fill", color: .red) {
                    activeSheet = .reportIssue
                }
                QuickActionBtn(title: "Add Part", icon: "plus.circle.fill", color: .green) {
                    activeSheet = .addTransferItem
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Inventory (Truck Stock vs Transfer)

    private var inventorySection: some View {
        Section {
            Picker("Inventory", selection: $inventoryTab) {
                ForEach(InventoryTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch inventoryTab {
            case .truckStock:
                if truckStock.isEmpty {
                    Text("No truck stock items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(truckStock) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.partName).font(.subheadline)
                                Text("Qty: \(item.quantity)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let target = item.targetQty, target > 0 {
                                ProgressView(
                                    value: min(Double(item.quantity), Double(target)),
                                    total: Double(target)
                                )
                                .tint(
                                    item.quantity < (item.minQty ?? 0) ? .red :
                                    item.quantity >= target ? .green : .orange
                                )
                                .frame(width: 60)
                            }
                        }
                    }
                }

            case .transfer:
                if transferItems.isEmpty {
                    Text("No items in transit")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transferItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.partName).font(.subheadline)
                                Text("\(item.sourceLocation ?? "?") → \(item.destinationLocation ?? "?")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("×\(item.quantity)")
                                .font(.subheadline).monospacedDigit()
                        }
                    }
                }
            }
        } header: {
            Text("Inventory")
        }
    }

    // MARK: - Trailer

    @ViewBuilder
    private var trailerSection: some View {
        if let stats = vehicleStats, stats.hasTrailer {
            Section {
                HStack {
                    Image(systemName: "truck.box.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(stats.trailerName ?? "Trailer")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Attached")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    // Navigation to trailer detail (48C)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            } header: {
                Text("Trailer")
            }
        }
    }

    // MARK: - Recent Mileage

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

    // MARK: - Recent Fuel

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

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .logFuel:
            if let vid = vehicleStats?.vehicleId, vid > 0 {
                LogFuelSheet(
                    vehicleId: vid,
                    onComplete: {
                        activeSheet = nil
                        loadData()
                    }
                )
                .environmentObject(appCore)
            } else {
                ContentUnavailableView("No vehicle assigned", systemImage: "car.2", description: Text("Assign a vehicle before logging fuel."))
            }

        case .reportIssue:
            ReportVehicleIssueSheet(
                vehicleName: vehicle?.vehicleName ?? "Vehicle",
                onComplete: {
                    activeSheet = nil
                }
            )

        case .addTransferItem:
            if let vid = vehicleStats?.vehicleId, vid > 0 {
                AddTransferItemSheet(
                    vehicleId: vid,
                    onComplete: {
                        activeSheet = nil
                        loadData()
                    }
                )
                .environmentObject(appCore)
            } else {
                ContentUnavailableView("No vehicle assigned", systemImage: "car.2", description: Text("Assign a vehicle before transferring parts."))
            }

        case .help:
            PageHelpSheet(
                title: "My Truck Help",
                sections: [
                    ("Overview", "My Truck is your personal vehicle dashboard. It shows the vehicle assigned to you with key stats, inventory, quick actions, attached trailer info, and recent mileage and fuel logs."),
                    ("Smart Cards", "The colored cards at the top show counts for tools on your truck, spare parts loaded, fuel tank level, maintenance items due, and transfer items in transit. Red or orange colors indicate something needs attention."),
                    ("Quick Actions", "Use Log Fuel to record a fill-up, Report Issue to flag a vehicle problem to fleet management, and Add Part to add a transfer item to your truck."),
                    ("Inventory", "Switch between Truck Stock (parts that stay on your truck) and Transfer (items being moved between locations). Progress bars show how your stock levels compare to targets."),
                    ("Trailer", "If a trailer is attached to your vehicle, it appears in the Trailer section. Tap the row to see trailer details."),
                    ("No Vehicle?", "If you see 'No Vehicle Assigned,' contact your supervisor to get a vehicle assigned to your account."),
                    ("Tips", "Pull down to refresh all data. Keep your fuel level and mileage updated regularly. Use the Report Issue button immediately when you notice a vehicle problem — do not wait.")
                ]
            )
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
        guard let fleet = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = vehicle == nil
        loadError = nil

        do {
            guard let currentUserId = appCore.currentUser?.id else {
                vehicle = nil
                isLoading = false
                return
            }

            // Get smart card stats
            vehicleStats = try fleet.getMyVehicleStats(userId: currentUserId)

            if let stats = vehicleStats {
                // Load vehicle detail
                vehicle = try fleet.getVehicleDetail(id: stats.vehicleId)

                // Load inventory by type
                truckStock = try fleet.getVehicleStock(vehicleId: stats.vehicleId, stockType: "truck_stock")
                transferItems = try fleet.getVehicleStock(vehicleId: stats.vehicleId, stockType: "transfer")

                // Load recent logs
                recentMileage = try fleet.listMileageLogs(vehicleId: stats.vehicleId, limit: 5)
                recentFuel = try fleet.listFuelLogs(vehicleId: stats.vehicleId, limit: 5)
            } else {
                vehicle = nil
                truckStock = []
                transferItems = []
                recentMileage = []
                recentFuel = []
            }
        } catch {
            loadError = userFriendlyError(error, context: "load truck data")
        }
        isLoading = false
    }
}

// MARK: - Smart Card Component

private struct MyVehicleSmartCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
        }
        .padding(10)
        .frame(minWidth: 90)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Quick Action Button

private struct QuickActionBtn: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Fuel Sheet

private struct LogFuelSheet: View {
    let vehicleId: Int64
    let onComplete: () -> Void
    @EnvironmentObject private var appCore: AppCore
    @State private var fuelPercent: Double = 100
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuel Level") {
                    VStack(spacing: 12) {
                        Text("\(Int(fuelPercent))%")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                fuelPercent < 25 ? .red :
                                fuelPercent < 50 ? .orange : .green
                            )
                        Slider(value: $fuelPercent, in: 0...100, step: 5)
                    }
                    .padding(.vertical, 4)
                }

                if let error = saveError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log Fuel Level")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFuel()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveFuel() {
        guard let fleet = appCore.fleetService else {
            saveError = "Fleet service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try fleet.logFuelLevel(vehicleId: vehicleId, fuelLevel: fuelPercent / 100.0)
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save vehicle data")
        }
        isSaving = false
    }
}

// MARK: - Report Vehicle Issue Sheet

private struct ReportVehicleIssueSheet: View {
    let vehicleName: String
    let onComplete: () -> Void
    @State private var description: String = ""
    @State private var severity: String = "low"

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    Text(vehicleName).font(.headline)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Critical").tag("critical")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Description") {
                    TextField("Describe the issue...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("This will be sent to fleet management for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report Issue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { onComplete() }
                        .disabled(description.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Transfer Item Sheet

private struct AddTransferItemSheet: View {
    let vehicleId: Int64
    let onComplete: () -> Void
    @EnvironmentObject private var appCore: AppCore
    @State private var partName: String = ""
    @State private var quantity: Int = 1
    @State private var source: String = ""
    @State private var destination: String = ""
    @State private var reason: String = "job_delivery"
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    TextField("Part name", text: $partName)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }

                Section("Transfer Details") {
                    TextField("Source location", text: $source)
                    TextField("Destination", text: $destination)
                    Picker("Reason", selection: $reason) {
                        Text("Job Delivery").tag("job_delivery")
                        Text("Return").tag("return")
                        Text("Restock").tag("restock")
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Transfer Item")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveTransferItem()
                    }
                    .disabled(partName.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveTransferItem() {
        guard let fleet = appCore.fleetService else {
            saveError = "Fleet service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try fleet.addVehicleStockItem(
                vehicleId: vehicleId,
                partName: partName,
                quantity: quantity,
                stockType: "transfer",
                sourceLocation: source.isEmpty ? nil : source,
                destinationLocation: destination.isEmpty ? nil : destination,
                transferReason: reason
            )
            onComplete()
        } catch {
            saveError = userFriendlyError(error, context: "save vehicle data")
        }
        isSaving = false
    }
}
