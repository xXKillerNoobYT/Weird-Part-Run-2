import SwiftUI
import WiredPartCore

/// Daily reports summary page showing per-job activity for a specific date.
///
/// Displays a table of jobs that had labor activity on the selected date,
/// with worker count, total hours, and job status columns. Date picker
/// in the toolbar defaults to today.
struct DailyReportsSummaryPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var reports: [ReportsService.DailyReportSummaryRow] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var selectedDate = Date()

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ReportsService.DailyReportSummaryRow.jobName)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Summary")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(reports.count) job\(reports.count == 1 ? "" : "s") active · \(String(format: "%.1f", totalHours)) total hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: selectedDate) { loadData() }

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var totalHours: Double {
        reports.reduce(0) { $0 + $1.totalHours }
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading daily summary...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if reports.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No activity")
                    .font(.headline)
                Text("No labor entries recorded for the selected date.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedReports, sortOrder: $sortOrder) {
                TableColumn("Job Name", value: \.jobName) { row in
                    Text(row.jobName)
                        .fontWeight(.medium)
                }
                .width(min: 180, ideal: 280)

                TableColumn("Workers", value: \.workerCount) { row in
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(row.workerCount)")
                            .font(.callout)
                    }
                }
                .width(min: 80, ideal: 100)

                TableColumn("Total Hours", value: \.totalHours) { row in
                    Text(String(format: "%.1f", row.totalHours))
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Status", value: \.status) { row in
                    statusBadge(row.status)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedReports: [ReportsService.DailyReportSummaryRow] {
        reports.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: selectedDate)

        do {
            let service = ReportsService(db: db)
            reports = try service.getDailyReportSummary(date: dateStr)
        } catch {
            print("[DailyReportsSummaryPage] Load error: \(error)")
        }

        isLoading = false
    }
}
