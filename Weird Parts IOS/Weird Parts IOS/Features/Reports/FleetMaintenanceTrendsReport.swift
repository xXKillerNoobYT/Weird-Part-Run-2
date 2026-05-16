import SwiftUI
import WiredPartCore

/// Maintenance cost trends over time with per-record detail.
struct FleetMaintenanceTrendsReport: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var trendData: [FleetService.MaintenanceTrendRow] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        List {
            StandardFilterBar(selectedRange: $dateRange, customStart: $startDate, customEnd: $endDate)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if let error = loadError {
                Section {
                    ErrorStateView(message: error) { loadData() }
                }
            }

            if isLoading {
                Section { ProgressView("Loading...") }
            } else if trendData.isEmpty {
                Section {
                    ContentUnavailableView("No Maintenance Data",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("No maintenance records found for this period."))
                }
            } else {
                Section("Summary") {
                    LabeledContent("Total Cost") {
                        Text("$\(totalCost, specifier: "%.2f")")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Records") {
                        Text("\(trendData.count)")
                    }
                    LabeledContent("Avg Cost/Record") {
                        Text("$\(avgCost, specifier: "%.2f")")
                    }
                }

                Section("Maintenance Records") {
                    ForEach(trendData) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.vehicleName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("$\(row.cost, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            HStack {
                                Text(row.maintenanceType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatDate(row.performedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Maintenance Trends")
        .reportExportToolbar(
            title: "Maintenance Trends Report",
            columns: ["Vehicle", "Type", "Cost", "Date"],
            rows: trendData.map { [$0.vehicleName, $0.maintenanceType,
                                    String(format: "%.2f", $0.cost),
                                    formatDate($0.performedAt)] }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Maintenance Trends Help", sections: [
                ("What This Page Does", "Lists all maintenance records for your fleet in the selected date range. Shows total cost, number of records, and average cost per maintenance event. Each record shows the vehicle, type of work, cost, and date."),
                ("How to Use It", "Pick a date range at the top. The summary gives you totals. Scroll through individual records to see what work was done. Export to PDF or CSV for fleet management reviews."),
                ("Tips", "If a single vehicle keeps showing up with high costs, it may be time to consider replacing it. Track trends month over month to budget for upcoming maintenance needs.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsFleetMaintenanceTrendsPageInactive, object: nil)
        }
    }

    private var totalCost: Double { trendData.reduce(0) { $0 + $1.cost } }
    private var avgCost: Double { trendData.isEmpty ? 0 : totalCost / Double(trendData.count) }

    private func formatDate(_ str: String) -> String {
        // Extract date portion from ISO string
        String(str.prefix(10))
    }

    private func loadData() {
        isLoading = true
        loadError = nil
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }
        do {
            trendData = try service.getMaintenanceTrendsReport(
                startDate: startDate, endDate: endDate
            )
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let context = """
        Fleet Maintenance Trends report page. Records: \(trendData.count). Date range: \(startDate.formatted(date: .abbreviated, time: .omitted)) to \(endDate.formatted(date: .abbreviated, time: .omitted)). Total maintenance cost: \(String(format: "%.2f", totalCost)). Avg cost per record: \(String(format: "%.2f", avgCost)). Error state: \(loadError ?? "none"). Available read-only actions: summarize maintenance spend concentration, explain average maintenance cost, identify high-cost periods.
        """
        NotificationCenter.default.post(name: .reportsFleetMaintenanceTrendsPageActive, object: nil, userInfo: ["context": context])
    }
}
