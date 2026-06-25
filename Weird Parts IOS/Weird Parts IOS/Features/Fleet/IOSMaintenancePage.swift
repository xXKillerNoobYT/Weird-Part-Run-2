import SwiftUI
import WiredPartCore

/// Maintenance records list page for iOS.
///
/// Displays a list of vehicle maintenance records with vehicle name,
/// maintenance type, date, cost, and odometer reading.
/// Supports pull-to-refresh and search filtering.
struct IOSMaintenancePage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @State private var records: [FleetService.MaintenanceRow] = []
    @State private var isInitialLoading = true
    @State private var isRefreshing = false
    @State private var hasLoadedOnce = false
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
            OnboardingBanner(pageId: "fleet-maintenance")
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            maintenanceList
        }
            .task { appCore.onboardingManager?.markCompleted("fleet-maintenance-view") }
            .navigationTitle("Maintenance")
            .searchable(text: $searchText, prompt: "Search maintenance records...")
            .onChange(of: searchText) { _, _ in postFleetMaintenanceContext() }
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadData() }
            }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
            .onAppear { postFleetMaintenanceContext() }
            .onDisappear {
                NotificationCenter.default.post(name: .fleetMaintenancePageInactive, object: nil)
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
                    title: "Maintenance Help",
                    sections: [
                        ("Overview", "This page lists all maintenance records across the fleet. Each record shows the vehicle, type of service performed, date, who did the work, cost, and odometer reading at the time."),
                        ("Searching", "Use the search bar to filter by vehicle name, maintenance type, or technician name. This helps you quickly find service history for a specific truck."),
                        ("Reading Entries", "The orange wrench icon marks each record. Vehicle name and maintenance type appear on the left. Cost and mileage appear on the right."),
                        ("Tips", "Regular maintenance keeps trucks on the road. Check this page to verify completed services and track spending. The Fleet Dashboard also highlights upcoming and overdue maintenance items.")
                    ]
                )
            }
    }

    // MARK: - Maintenance List

    private var fleetMaintenanceContext: String {
        let searchState = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : "active"
        return "page=Fleet Maintenance; total_records=\(records.count); visible_records=\(filteredRecords.count); date_range=\(dateRange.rawValue); search=\(searchState)"
    }

    private func postFleetMaintenanceContext() {
        NotificationCenter.default.post(
            name: .fleetMaintenancePageActive,
            object: nil,
            userInfo: ["context": fleetMaintenanceContext]
        )
    }

    @ViewBuilder
    private var maintenanceList: some View {
        Group {
            if isInitialLoading {
                ProgressView("Loading maintenance records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredRecords.isEmpty {
                EmptyStateView(
                    icon: "wrench.and.screwdriver",
                    title: "No Maintenance Records",
                    message: "No maintenance records found."
                )
            } else {
                List(filteredRecords, id: \.id) { record in
                    maintenanceRow(record)
                }
                .listStyle(.insetGrouped)
            }
        }
        .overlay(alignment: .top) {
            refreshingOverlay
        }
    }

    @ViewBuilder
    private var refreshingOverlay: some View {
        if isRefreshing {
            ProgressView()
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.opacity)
                .accessibilityLabel("Refreshing maintenance records")
        }
    }

    private var filteredRecords: [FleetService.MaintenanceRow] {
        guard !searchText.isEmpty else { return records }
        let query = searchText.lowercased()
        return records.filter {
            $0.vehicleName.lowercased().contains(query) ||
            ($0.maintenanceTypeName?.lowercased().contains(query) ?? false) ||
            ($0.performedByName?.lowercased().contains(query) ?? false)
        }
    }

    private func maintenanceRow(_ record: FleetService.MaintenanceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.vehicleName)
                    .fontWeight(.medium)
                if let typeName = record.maintenanceTypeName {
                    Text(typeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(record.performedAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let performer = record.performedByName {
                        Text("by \(performer)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let cost = record.cost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                if let odo = record.odometerReading {
                    Text("\(odo.formatted()) mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            hasLoadedOnce = true
            isInitialLoading = false
            isRefreshing = false
            return
        }

        if hasLoadedOnce {
            isRefreshing = true
        } else {
            isInitialLoading = true
        }

        DispatchQueue.main.async {
            defer {
                self.hasLoadedOnce = true
                self.isInitialLoading = false
                self.isRefreshing = false
            }

            self.loadError = nil
            do {
                let startStr = Formatters.localDateFormatter.string(from: self.effectiveStart)
                let endStr = Formatters.localDateFormatter.string(from: self.effectiveEnd)
                self.records = try service.listMaintenanceRecords(start: startStr, end: endStr)
            } catch {
                self.loadError = userFriendlyError(error, context: "load maintenance data")
            }
        }
    }
}
