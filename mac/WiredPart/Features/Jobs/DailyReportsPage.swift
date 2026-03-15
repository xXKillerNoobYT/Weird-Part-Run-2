import SwiftUI
import GRDB
import WiredPartCore

/// Daily reports page showing auto-generated labor reports per job.
///
/// Displays a table of daily reports with job name, report date, status,
/// and generator. Reports summarize the day's labor activity for each job.
struct DailyReportsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var reports: [JobsService.DailyReportRow] = []
    @State private var isLoading = true
    @State private var sortOrder = [KeyPathComparator(\JobsService.DailyReportRow.reportDate, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            reportContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadReports() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Reports")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(reports.count) reports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadReports()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var reportContent: some View {
        if isLoading {
            ProgressView("Loading reports...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if reports.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No daily reports")
                    .font(.headline)
                Text("Reports are generated when labor entries are completed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedReports, sortOrder: $sortOrder) {
                TableColumn("Date", value: \.reportDate) { report in
                    Text(report.reportDate)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 100, ideal: 120)

                TableColumn("Job", value: \.jobName) { report in
                    Text(report.jobName)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Status", value: \.status) { report in
                    statusBadge(report.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Reviewed By") { report in
                    Text(report.reviewedByName ?? "—")
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 150)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedReports: [JobsService.DailyReportRow] {
        reports.sorted(using: sortOrder)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "generated": .green
        case "reviewed": .blue
        case "draft": .orange
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadReports() {
        guard let service = appCore.jobsService else { return }
        isLoading = true
        do {
            reports = try service.listReports()
        } catch {
            print("[DailyReportsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
