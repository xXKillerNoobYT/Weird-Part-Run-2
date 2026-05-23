import SwiftUI
import WiredPartCore

/// Daily reports page for iOS.
///
/// Lists daily reports with job name, date, status, and generator.
/// Supports pull-to-refresh and shows report details inline.
struct JobReportsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var reports: [JobsService.DailyReportRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private var filteredReports: [JobsService.DailyReportRow] {
        guard !searchText.isEmpty else { return reports }
        let query = searchText.lowercased()
        return reports.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.reportDate.lowercased().contains(query) ||
            $0.status.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "jobs-reports")
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            reportContent
        }
        .task { appCore.onboardingManager?.markCompleted("job-reports-view") }
            .navigationTitle("Daily Reports")
            .searchable(text: $searchText, prompt: "Search by job name or date...")
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
                    title: "Job Reports Help",
                    sections: [
                        ("Overview", "Browse daily reports across all jobs. Each report shows the job name, date, status, and who reviewed it."),
                        ("Search", "Use the search bar to filter reports by job name, date, or status."),
                        ("Details", "Reports are generated automatically from daily job activity and clock entries. Pull down to refresh.")
                    ]
                )
            }
            .refreshable { loadReports() }
            .task { loadReports() }
            .onChange(of: dateRange) { loadReports() }
            .onChange(of: customStart) { loadReports() }
            .onChange(of: customEnd) { loadReports() }
            .onDisappear {
                NotificationCenter.default.post(name: .jobReportsPageInactive, object: nil)
            }
            .onChange(of: searchText) { _, _ in postAIContext() }
            .onChange(of: activeSheet?.id) { _, _ in postAIContext() }
    }

    // MARK: - Content

    @ViewBuilder
    private var reportContent: some View {
        if isLoading {
            ProgressView("Loading reports...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadReports() }
        } else if reports.isEmpty {
            EmptyStateView(
                icon: "doc.plaintext",
                title: "No Reports",
                message: "Daily reports will appear here when generated."
            )
        } else {
            List(filteredReports, id: \.id) { report in
                reportRow(report)
            }
            .listStyle(.insetGrouped)
        }
    }

    private func reportRow(_ report: JobsService.DailyReportRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.reportDate)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(report.status)
            }

            Text(report.jobName)
                .fontWeight(.medium)

            HStack {
                if let reviewer = report.reviewedByName {
                    Label(reviewer, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "generated": .green
        case "reviewed": .blue
        case "draft": .orange
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadReports() {
        guard let service = appCore.jobsService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = reports.isEmpty
        loadError = nil
        do {
            reports = try service.listReports()
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load job reports")
        }
        isLoading = false
    }

    private func postAIContext() {
        let statusCounts = Dictionary(grouping: reports, by: \.status)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Job Reports page. Read-only context.
        Date range: \(dateRange.rawValue), search active: \(!searchText.isEmpty).
        Reports loaded: \(reports.count), visible reports: \(filteredReports.count), status counts: \(statusCounts.isEmpty ? "none" : statusCounts).
        Custom date range active: \(dateRange == .custom), start: \(customStart), end: \(customEnd).
        Available read-only guidance: explain report rows, status badges, date range filters, search state, and help/refresh controls. Do not create or update reports directly.
        """
        NotificationCenter.default.post(
            name: .jobReportsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
