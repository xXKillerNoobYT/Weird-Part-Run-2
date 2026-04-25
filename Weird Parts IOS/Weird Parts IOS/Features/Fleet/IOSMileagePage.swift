import SwiftUI
import WiredPartCore

/// Mileage logs list page for iOS.
///
/// Displays a list of vehicle mileage logs with vehicle name,
/// user, date, total miles, and purpose. Supports pull-to-refresh
/// and search filtering.
struct IOSMileagePage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var mileageLogs: [FleetService.MileageRow] = []
    @State private var isLoading = true
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
            mileageList
        }
            .navigationTitle("Mileage Logs")
            .searchable(text: $searchText, prompt: "Search mileage logs...")
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadData() }
            }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
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
                    title: "Mileage Logs Help",
                    sections: [
                        ("Overview", "This page lists all mileage logs across the fleet. Each entry shows the vehicle, driver, date, total miles driven, and the trip purpose."),
                        ("Searching", "Use the search bar to filter by vehicle name, driver name, or trip purpose. This is useful when you need to find mileage for a specific job or driver."),
                        ("Reading Entries", "Each row shows the vehicle name on the left with the driver underneath. On the right you will see total miles and the log date."),
                        ("Tips", "Pull down to refresh the list. Mileage logs are created automatically when drivers complete trips or manually from the vehicle detail page. Keep mileage up to date for accurate reimbursement calculations.")
                    ]
                )
            }
    }

    // MARK: - Mileage List

    @ViewBuilder
    private var mileageList: some View {
        if isLoading {
            ProgressView("Loading mileage logs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredLogs.isEmpty {
            ContentUnavailableView {
                Label("No Mileage Logs", systemImage: "road.lanes")
            } description: {
                Text("No mileage logs found.")
            }
        } else {
            List(filteredLogs, id: \.id) { log in
                mileageRow(log)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredLogs: [FleetService.MileageRow] {
        guard !searchText.isEmpty else { return mileageLogs }
        let query = searchText.lowercased()
        return mileageLogs.filter {
            $0.vehicleName.lowercased().contains(query) ||
            $0.userName.lowercased().contains(query) ||
            ($0.purpose?.lowercased().contains(query) ?? false)
        }
    }

    private func mileageRow(_ log: FleetService.MileageRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.vehicleName)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Label(log.userName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let purpose = log.purpose, !purpose.isEmpty {
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let miles = log.totalMiles {
                    Text(String(format: "%.1f mi", miles))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(log.logDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        isLoading = mileageLogs.isEmpty
        loadError = nil
        do {
            mileageLogs = try service.listMileageLogs()
        } catch {
            loadError = userFriendlyError(error, context: "load mileage data")
        }
        isLoading = false
    }
}
