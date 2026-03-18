import SwiftUI
import WiredPartCore

/// Labor overview page showing cross-job hours, overtime, and drive time.
struct IOSLaborOverviewPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var timesheetRows: [ReportsService.TimesheetRow] = []
    @State private var totalRegular: Double = 0
    @State private var totalOvertime: Double = 0
    @State private var totalHours: Double = 0
    @State private var uniqueWorkers: Int = 0

    var body: some View {
        VStack(spacing: 0) {
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
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var laborContent: some View {
        List {
            Section("This Week") {
                statRow("Total Hours", String(format: "%.1f hrs", totalHours), icon: "clock.fill", color: .blue)
                statRow("Regular", String(format: "%.1f hrs", totalRegular), icon: "clock", color: .green)
                statRow("Overtime", String(format: "%.1f hrs", totalOvertime), icon: "exclamationmark.circle.fill", color: .orange)
                statRow("Active Workers", "\(uniqueWorkers)", icon: "person.2.fill", color: .purple)
            }

            Section("By Employee") {
                if timesheetRows.isEmpty {
                    Text("No labor entries this week.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(timesheetRows) { row in
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func statRow(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
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
            loadError = "Failed to load labor data: \(error.localizedDescription)"
            print("[IOSLaborOverviewPage] Load error: \(error)")
        }
        isLoading = false
    }
}
