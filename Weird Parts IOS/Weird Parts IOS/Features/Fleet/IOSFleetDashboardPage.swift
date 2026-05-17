import SwiftUI
import WiredPartCore

/// Fleet dashboard page showing KPI smart cards, vehicle status list,
/// cost summary (hat-gated), upcoming maintenance, and fleet report link.
///
/// Uses FleetService methods: getFleetDashboardStats(), getVehicleStatusList(),
/// getUpcomingFleetMaintenance(), listMaintenanceRecords().
struct IOSFleetDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var dashStats: FleetService.FleetDashboardStats?
    @State private var vehicles: [FleetService.VehicleStatusItem] = []
    @State private var upcomingMaintenance: [FleetService.FleetMaintenanceItem] = []
    @State private var recentMaintenance: [FleetService.MaintenanceRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "fleet-dashboard")

            if isLoading {
                ProgressView("Loading fleet dashboard...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                dashboardContent
            }
        }
        .navigationTitle("Fleet Dashboard")
        .refreshable { loadData() }
        .background(DS.Background.page)
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("fleet-dashboard-view")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Fleet Dashboard Help",
                sections: [
                    ("Overview", "The Fleet Dashboard gives you a bird's-eye view of every vehicle, trailer, and maintenance item in the fleet. Smart cards at the top show key counts at a glance."),
                    ("Status Cards", "The first row shows total vehicles, how many are active, how many have maintenance due, overdue inspections, and total trailers. Tap to scan quickly for anything that needs attention."),
                    ("Cost Cards", "If you have financial permissions, a second row shows month-to-date fuel spend, miles driven, and maintenance costs. These update as new logs are entered."),
                    ("Vehicle List", "Scroll down to see every vehicle with its current driver, status, and whether today's pre-trip inspection has been completed. Tap a vehicle to open its detail page."),
                    ("Upcoming Maintenance", "Shows vehicles with scheduled maintenance approaching. Overdue items appear in red so nothing slips through the cracks."),
                    ("Tips", "Pull down to refresh data at any time. Check this dashboard at the start of each day to spot overdue inspections and upcoming maintenance before trucks roll out.")
                ]
            )
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Row 1: Fleet status smart cards
                fleetStatusCards

                // Row 2: Cost smart cards (hat-gated)
                costCards

                // Vehicle status list
                vehicleStatusSection

                // Upcoming maintenance
                upcomingMaintenanceSection

                // Recent maintenance activity
                recentActivitySection

                // Fleet reports link
                fleetReportsSection
            }
            .padding()
        }
    }

    // MARK: - Fleet Status Cards (Row 1)

    private var fleetStatusCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                dashboardSmartCard(
                    title: "Vehicles",
                    value: "\(dashStats?.totalVehicles ?? 0)",
                    icon: "car.fill",
                    color: .blue
                )
                dashboardSmartCard(
                    title: "Active",
                    value: "\(dashStats?.activeVehicles ?? 0)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                dashboardSmartCard(
                    title: "Maint. Due",
                    value: "\(dashStats?.maintenanceDue ?? 0)",
                    icon: "wrench.fill",
                    color: (dashStats?.maintenanceDue ?? 0) > 0 ? .orange : .green
                )
                dashboardSmartCard(
                    title: "Overdue Inspect",
                    value: "\(dashStats?.overdueInspections ?? 0)",
                    icon: "exclamationmark.triangle.fill",
                    color: (dashStats?.overdueInspections ?? 0) > 0 ? .red : .green
                )
                dashboardSmartCard(
                    title: "Trailers",
                    value: "\(dashStats?.totalTrailers ?? 0)",
                    icon: "shippingbox.fill",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Cost Cards (Row 2 — Hat-Gated)

    @ViewBuilder
    private var costCards: some View {
        if appCore.hasPermission("view_fleet_financials"), let stats = dashStats {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let fuelCost = stats.fuelCostMTD {
                        dashboardSmartCard(
                            title: "Fuel MTD",
                            value: "$\(Int(fuelCost))",
                            icon: "fuelpump.fill",
                            color: .orange
                        )
                    }
                    if let miles = stats.milesMTD {
                        dashboardSmartCard(
                            title: "Miles MTD",
                            value: "\(miles.formatted())",
                            icon: "speedometer",
                            color: .blue
                        )
                    }
                    if let maintCost = stats.maintenanceCostMTD {
                        dashboardSmartCard(
                            title: "Maint. MTD",
                            value: "$\(Int(maintCost))",
                            icon: "wrench.and.screwdriver.fill",
                            color: .red
                        )
                    }
                }
            }
        }
    }

    // MARK: - Smart Card Component

    private func dashboardSmartCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 120)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Vehicle Status List

    @ViewBuilder
    private var vehicleStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vehicles")
                    .font(.headline)
                Spacer()
                Text("\(vehicles.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if vehicles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "car")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No vehicles found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                let todayString = Formatters.localDateFormatter.string(from: Date())

                VStack(spacing: 0) {
                    ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, vehicle in
                        NavigationLink(value: vehicle.id) {
                            vehicleStatusRow(vehicle, todayString: todayString)
                        }
                        .buttonStyle(.plain)

                        if index < vehicles.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func vehicleStatusRow(_ vehicle: FleetService.VehicleStatusItem, todayString: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vehicleIcon(vehicle.vehicleType))
                .font(.body)
                .foregroundStyle(statusColor(vehicle.status))
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.vehicleName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let driver = vehicle.driverName {
                    Text(driver)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unassigned")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(vehicle.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(statusColor(vehicle.status))

                if let inspDate = vehicle.lastInspectionDate {
                    let isToday = inspDate.hasPrefix(todayString)
                    Text(isToday ? "Inspected" : "No inspection today")
                        .font(.caption2)
                        .foregroundStyle(isToday ? .green : .red)
                } else {
                    Text("Never inspected")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Upcoming Maintenance

    @ViewBuilder
    private var upcomingMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Maintenance")
                .font(.headline)
                .padding(.horizontal, 4)

            if upcomingMaintenance.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No upcoming maintenance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingMaintenance.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text(item.vehicleName)
                                .font(.subheadline)
                            Spacer()
                            let days = Int(item.daysUntil)
                            if days < 0 {
                                Text("Overdue \(abs(days))d")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.red)
                            } else if days == 0 {
                                Text("Due Today")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("In \(days)d")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        if index < upcomingMaintenance.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Recent Maintenance Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Maintenance")
                .font(.headline)
                .padding(.horizontal, 4)

            if recentMaintenance.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No recent maintenance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMaintenance.enumerated()), id: \.element.id) { index, record in
                        maintenanceActivityRow(record)

                        if index < recentMaintenance.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func maintenanceActivityRow(_ record: FleetService.MaintenanceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.vehicleName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let typeName = record.maintenanceTypeName {
                        Text(typeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let performer = record.performedByName {
                        Text("by \(performer)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let cost = record.cost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(String(record.performedAt.prefix(10)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Fleet Reports Link

    private var fleetReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analytics")
                .font(.headline)
                .padding(.horizontal, 4)

            NavigationLink {
                Text("Fleet Reports")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } label: {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("Fleet Reports")
                        .font(.subheadline)
                    Spacer()
                    Text("Fuel, Mileage, Maintenance trends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func vehicleIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "van": return "car.fill"
        case "truck": return "truck.box.fill"
        case "pickup": return "suv.side.fill"
        default: return "car.fill"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "active": return .green
        case "inactive", "out_of_service": return .red
        case "maintenance": return .orange
        default: return .secondary
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = dashStats == nil
        loadError = nil

        do {
            dashStats = try service.getFleetDashboardStats()
            vehicles = try service.getVehicleStatusList()
            upcomingMaintenance = try service.getUpcomingFleetMaintenance(limit: 10)
            recentMaintenance = try service.listMaintenanceRecords(limit: 5)
        } catch {
            loadError = userFriendlyError(error, context: "load fleet dashboard")
        }

        isLoading = false
    }
}
