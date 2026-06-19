import SwiftUI
import WiredPartCore

/// Daily reports page for iOS.
///
/// Displays per-job activity for a selected date, showing job name, worker
/// count, total hours, and status. Uses `ReportsService.getDailyReportSummary(date:)`
/// and supports date navigation with previous/next buttons plus pull-to-refresh.
struct IOSDailyReportsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var reports: [ReportsService.DailyReportSummaryRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        VStack(spacing: 0) {
            datePicker
            reportContent
        }
        .navigationTitle("Daily Reports")
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
                title: "Daily Reports Help",
                sections: [
                    ("Overview", "View per-job activity summaries for any date. See worker count, total hours logged, and report status for each job."),
                    ("Navigation", "Use the left/right arrows to move between dates. Tap 'Today' to jump back to the current date."),
                    ("Data", "Pull down to refresh. Reports are generated automatically based on clock entries and job activity.")
                ]
            )
        }
        .searchable(text: $searchText, prompt: "Search jobs...")
        .onChange(of: searchText) { _, _ in postAIContext(dateString: isoDate(selectedDate)) }
        .refreshable { loadData() }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .dailyReportsPageInactive, object: nil)
        }
    }

    // MARK: - Date Picker

    private var datePicker: some View {
        HStack(spacing: 16) {
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

            VStack(spacing: 2) {
                Text(formattedDate(selectedDate))
                    .font(.headline)
                if Calendar.current.isDateInToday(selectedDate) {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next day")
            .disabled(Calendar.current.isDateInToday(selectedDate))

            Button {
                selectedDate = Date()
                loadData()
            } label: {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if isLoading {
            ProgressView("Loading reports...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if reports.isEmpty {
            EmptyStateView(
                icon: "doc.plaintext",
                title: "No Activity",
                message: "No job activity was recorded for \(formattedDate(selectedDate))."
            )
        } else {
            List {
                // Summary header
                Section {
                    HStack(spacing: 16) {
                        summaryCard(
                            title: "Jobs",
                            value: "\(reports.count)",
                            icon: "hammer.fill",
                            color: .blue
                        )
                        summaryCard(
                            title: "Workers",
                            value: "\(totalWorkers)",
                            icon: "person.2.fill",
                            color: .green
                        )
                        summaryCard(
                            title: "Hours",
                            value: String(format: "%.1f", totalHours),
                            icon: "clock.fill",
                            color: .orange
                        )
                    }
                    .padding(.vertical, 4)
                }

                // Per-job rows
                Section("Jobs") {
                    ForEach(filteredReports, id: \.id) { report in
                        reportRow(report)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Summary Card

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
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

    // MARK: - Report Row

    private func reportRow(_ report: ReportsService.DailyReportSummaryRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.jobName)
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Label("\(report.workerCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.1f hrs", report.totalHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge(report.status)
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

    // MARK: - Computed Properties

    private var filteredReports: [ReportsService.DailyReportSummaryRow] {
        if searchText.isEmpty { return reports }
        return reports.filter {
            $0.jobName.localizedCaseInsensitiveContains(searchText) ||
            $0.status.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalWorkers: Int {
        reports.reduce(0) { $0 + $1.workerCount }
    }

    private var totalHours: Double {
        reports.reduce(0) { $0 + $1.totalHours }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service unavailable"
            return
        }
        isLoading = reports.isEmpty
        let dateStr = isoDate(selectedDate)
        do {
            reports = try service.getDailyReportSummary(date: dateStr)
            postAIContext(dateString: dateStr)
        } catch {
            loadError = userFriendlyError(error, context: "load daily reports")
        }
        isLoading = false
    }

    private func postAIContext(dateString: String) {
        let statusCounts = Dictionary(grouping: reports, by: \.status)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Daily Reports page. Read-only context.
        Selected date: \(dateString), search active: \(!searchText.isEmpty).
        Reports loaded: \(reports.count), visible reports: \(filteredReports.count), total workers: \(totalWorkers), total hours: \(String(format: "%.1f", totalHours)).
        Status counts: \(statusCounts.isEmpty ? "none" : statusCounts).
        Available read-only guidance: explain date navigation, report summaries, status badges, search state, and where help/refresh controls are located. Do not create or edit reports directly.
        """
        NotificationCenter.default.post(
            name: .dailyReportsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
