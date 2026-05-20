import SwiftUI
import WiredPartCore

/// Labor overview page showing cross-job hours, overtime, and drive time.
struct IOSLaborOverviewPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var timesheetRows: [ReportsService.TimesheetRow] = []
    @State private var totalRegular: Double = 0
    @State private var totalOvertime: Double = 0
    @State private var totalHours: Double = 0
    @State private var uniqueWorkers: Int = 0
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            if isLoading {
                ProgressView("Loading labor data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                laborContent
            }
        }
        .navigationTitle("Labor Overview")
        .searchable(text: $searchText, prompt: "Search employees...")
        .reportExportToolbar(
            title: "Labor_Overview",
            columns: ["Employee", "Regular", "Overtime", "Total", "Days"],
            rows: timesheetRows.map { [$0.userName, String(format: "%.1f", $0.regularHours),
                                       String(format: "%.1f", $0.overtimeHours),
                                       String(format: "%.1f", $0.totalHours), "\($0.daysWorked)"] }
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
            PageHelpSheet(title: "Labor Overview Help", sections: [
                ("What This Page Does", "Gives you a high-level view of labor for the current week. Shows total hours, regular vs overtime, and the number of active workers. Below that, each employee is listed with their individual breakdown."),
                ("How to Use It", "The top section shows weekly totals. Scroll down to see each employee's regular hours, overtime, and days worked. Pull down to refresh if crews are still clocking in."),
                ("Tips", "Keep an eye on overtime numbers. If someone is already high mid-week, consider adjusting schedules. This report resets each Monday.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: dateRange) { loadData() }
        .onChange(of: customStart) { loadData() }
        .onChange(of: customEnd) { loadData() }
    }

    private var filteredTimesheetRows: [ReportsService.TimesheetRow] {
        if searchText.isEmpty { return timesheetRows }
        return timesheetRows.filter {
            $0.userName.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private var laborContent: some View {
        // Fix #219: when there's genuinely no labor data, show a clear empty state
        // instead of a page full of "0.0 hrs" stat rows that implies something loaded.
        if totalHours == 0 && timesheetRows.isEmpty {
            EmptyStateView(
                icon: "clock.badge.questionmark",
                title: "No Labor This Week",
                message: "No time was clocked this week. Labor entries will appear here once employees start clocking in."
            )
        } else {
            List {
            Section("This Week") {
                statRow("Total Hours", String(format: "%.1f hrs", totalHours), icon: "clock.fill", color: .blue)
                statRow("Regular", String(format: "%.1f hrs", totalRegular), icon: "clock", color: .green)
                statRow("Overtime", String(format: "%.1f hrs", totalOvertime), icon: "exclamationmark.circle.fill", color: .orange)
                statRow("Active Workers", "\(uniqueWorkers)", icon: "person.2.fill", color: .purple)
            }

            Section("By Employee") {
                if filteredTimesheetRows.isEmpty {
                    Text("No labor entries this week.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(filteredTimesheetRows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.userName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(row.daysWorked) day\(row.daysWorked == 1 ? "" : "s") worked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f hrs", row.totalHours))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if row.overtimeHours > 0 {
                                    Text(String(format: "+%.1f OT", row.overtimeHours))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func statRow(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service is not available."
            return
        }
        isLoading = timesheetRows.isEmpty
        loadError = nil

        // Get current week start (Monday) and end (Sunday)
        let cal = Calendar.current
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? today

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let startStr = f.string(from: weekStart)
        let endStr = f.string(from: weekEnd)

        do {
            timesheetRows = try service.getTimesheetData(startDate: startStr, endDate: endStr)
            totalRegular = timesheetRows.reduce(0) { $0 + $1.regularHours }
            totalOvertime = timesheetRows.reduce(0) { $0 + $1.overtimeHours }
            totalHours = timesheetRows.reduce(0) { $0 + $1.totalHours }
            uniqueWorkers = timesheetRows.count
        } catch {
            loadError = userFriendlyError(error, context: "load labor data")
        }
        isLoading = false
    }
}
