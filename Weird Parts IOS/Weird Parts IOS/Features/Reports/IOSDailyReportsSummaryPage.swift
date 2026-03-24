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
            dateNavigator
            summaryContent
        }
        .navigationTitle("Reports Summary")
        .reportExportToolbar(
            title: "Daily_Summary",
            columns: ["Job", "Workers", "Hours", "Status"],
            rows: rows.map { [$0.jobName, "\($0.workerCount)",
                              String(format: "%.1f", $0.totalHours), $0.status] }
        )
        .refreshable { loadData() }
        .task { loadData() }
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
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
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
                    ForEach(rows, id: \.id) { row in
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
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
