import SwiftUI
import WiredPartCore

/// Daily reports summary page for iOS.
///
/// Displays a date-picker-driven summary of all daily reports across jobs.
/// Each row shows job name, worker count, total hours, and status badge.
/// Uses `ReportsService.getDailyReportSummary(date:)` with date navigation.
struct IOSDailyReportsSummaryPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [ReportsService.DailyReportSummaryRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    private var displayDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            dateNavigator
            summaryContent
        }
        .navigationTitle("Reports Summary")
        .searchable(text: $searchText, prompt: "Search jobs...")
        .reportExportToolbar(
            title: "Daily_Summary",
            columns: ["Job", "Workers", "Hours", "Status"],
            rows: rows.map { [$0.jobName, "\($0.workerCount)",
                              String(format: "%.1f", $0.totalHours), $0.status] }
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
            PageHelpSheet(title: "Daily Reports Summary Help", sections: [
                ("What This Page Does", "Shows a quick snapshot of all daily reports across every active job for a single day. You can see how many workers were on each job, total hours logged, and the job status."),
                ("How to Use It", "Use the left and right arrows to move between days, or tap the date to pick a specific day. Each row shows a job with worker count, hours, and status. The top KPIs give you totals at a glance."),
                ("Tips", "Check this page at the end of each workday to make sure all jobs have reports filed. If a job shows zero workers, the foreman may not have submitted the daily report yet.")
            ])
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsDailySummaryPageInactive, object: nil)
        }
        .onChange(of: dateRange) { loadData() }
        .onChange(of: customStart) { loadData() }
        .onChange(of: customEnd) { loadData() }
    }

    // MARK: - Date Navigator

    private var dateNavigator: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            Spacer()

            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: selectedDate) { loadData() }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(Calendar.current.isDateInToday(selectedDate))
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Summary Content

    @ViewBuilder
    private var summaryContent: some View {
        if isLoading {
            ProgressView("Loading summary...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Reports", systemImage: "doc.plaintext")
            } description: {
                Text("No daily reports found for \(displayDate).")
            }
        } else {
            List {
                Section {
                    HStack(spacing: 16) {
                        kpiLabel(title: "Jobs", value: "\(rows.count)", icon: "hammer.fill", color: .blue)
                        kpiLabel(title: "Workers", value: "\(totalWorkers)", icon: "person.2.fill", color: .green)
                        kpiLabel(title: "Hours", value: String(format: "%.1f", totalHours), icon: "clock.fill", color: .orange)
                    }
                    .padding(.vertical, 4)
                }

                Section("Per-Job Activity") {
                    ForEach(filteredRows, id: \.id) { row in
                        jobRow(row)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - KPI Label

    private func kpiLabel(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Job Row

    private func jobRow(_ row: ReportsService.DailyReportSummaryRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.jobName)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Label("\(row.workerCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.1f hrs", row.totalHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge(row.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Computed

    private var filteredRows: [ReportsService.DailyReportSummaryRow] {
        if searchText.isEmpty { return rows }
        return rows.filter {
            $0.jobName.localizedCaseInsensitiveContains(searchText) ||
            $0.status.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalWorkers: Int { rows.reduce(0) { $0 + $1.workerCount } }
    private var totalHours: Double { rows.reduce(0) { $0 + $1.totalHours } }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service unavailable"
            return
        }
        isLoading = rows.isEmpty
        do {
            rows = try service.getDailyReportSummary(date: dateString)
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let workerCount = rows.reduce(0) { $0 + $1.workerCount }
        let totalHours = rows.reduce(0) { $0 + $1.totalHours }
        NotificationCenter.default.post(
            name: .reportsDailySummaryPageActive,
            object: nil,
            userInfo: [
                "context": "Daily Reports Summary: date \(dateString), \(rows.count) jobs, \(filteredRows.count) visible, \(workerCount) workers, \(String(format: "%.1f", totalHours)) hours."
            ]
        )
    }
}
