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

    var body: some View {
        reportContent
            .navigationTitle("Daily Reports")
            .refreshable { loadReports() }
            .task { loadReports() }
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
            ContentUnavailableView {
                Label("No Reports", systemImage: "doc.plaintext")
            } description: {
                Text("Daily reports will appear here when generated.")
            }
        } else {
            List(reports, id: \.id) { report in
                reportRow(report)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
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
        guard let service = appCore.jobsService else { return }
        isLoading = reports.isEmpty
        loadError = nil
        do {
            reports = try service.listReports()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
