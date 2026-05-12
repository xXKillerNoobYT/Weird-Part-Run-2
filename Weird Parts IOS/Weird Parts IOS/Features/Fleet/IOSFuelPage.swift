import SwiftUI
import WiredPartCore

/// Fuel log list page for iOS.
///
/// Displays a searchable list of fuel logs with vehicle name, date,
/// gallons, cost, and station. Uses FleetService.listFuelLogs().
/// Supports pull-to-refresh and search filtering.
struct IOSFuelPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var fuelLogs: [FleetService.FuelRow] = []
    @State private var isInitialLoading = true
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    // Date filter
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            fuelList
        }
            .navigationTitle("Fuel Logs")
            .searchable(text: $searchText, prompt: "Search fuel logs...")
            .refreshable { loadData(isRefresh: true) }
            .task { loadData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadData(isRefresh: !fuelLogs.isEmpty) }
            }
            .onChange(of: dateRange) { loadData(isRefresh: true) }
            .onChange(of: customStart) { loadData(isRefresh: true) }
            .onChange(of: customEnd) { loadData(isRefresh: true) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing fuel logs")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(
                    title: "Fuel Logs Help",
                    sections: [
                        ("Overview", "This page shows all fuel fill-up records across the fleet. Each entry includes the vehicle, date, gallons pumped, total cost, and the gas station name."),
                        ("Searching", "Use the search bar to filter by vehicle name, driver name, or gas station. Handy for tracking fuel purchases at a specific station or for a particular truck."),
                        ("Reading Entries", "The green fuel pump icon marks each entry. Vehicle name and date appear on the left. Cost and gallons appear on the right."),
                        ("Tips", "Drivers can log fuel from the My Truck page using the Log Fuel quick action. Keeping fuel logs accurate helps track fleet fuel costs on the dashboard and spending reports.")
                    ]
                )
            }
    }

    // MARK: - Fuel List

    @ViewBuilder
    private var fuelList: some View {
        if isInitialLoading {
            ProgressView("Loading fuel logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredLogs.isEmpty {
            ContentUnavailableView {
                Label("No Fuel Logs", systemImage: "fuelpump")
            } description: {
                Text("No fuel logs found.")
            }
        } else {
            List(filteredLogs, id: \.id) { log in
                fuelRow(log)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredLogs: [FleetService.FuelRow] {
        guard !searchText.isEmpty else { return fuelLogs }
        let query = searchText.lowercased()
        return fuelLogs.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.userName.lowercased().contains(query) ||
            ($0.station?.lowercased().contains(query) ?? false)
        }
    }

    private func fuelRow(_ log: FleetService.FuelRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fuelpump.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.vehicleName)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(log.logDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let station = log.station, !station.isEmpty {
                        Text(station)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let cost = log.totalCost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                if let gallons = log.gallons {
                    Text(String(format: "%.1f gal", gallons))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData(isRefresh: Bool = false) {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isInitialLoading = false
            isRefreshing = false
            return
        }
        let shouldShowInitialLoader = !isRefresh && fuelLogs.isEmpty
        isInitialLoading = shouldShowInitialLoader
        isRefreshing = !shouldShowInitialLoader
        loadError = nil
        defer {
            isInitialLoading = false
            isRefreshing = false
        }
        do {
            let startStr = Formatters.localDateFormatter.string(from: effectiveStart)
            let endStr = Formatters.localDateFormatter.string(from: effectiveEnd)
            fuelLogs = try service.listFuelLogs(start: startStr, end: endStr)
        } catch {
            loadError = userFriendlyError(error, context: "load fuel data")
        }
    }
}
