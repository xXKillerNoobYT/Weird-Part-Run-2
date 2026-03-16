import SwiftUI
import GRDB
import WiredPartCore

/// Pre-billing review page for iOS.
///
/// Displays job summaries with regular hours, overtime hours, and totals
/// for the selected date range. Uses direct SQL queries against the
/// labor_entries and jobs tables. Supports date range selection and
/// pull-to-refresh.
struct IOSPreBillingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [PreBillingRow] = []
    @State private var isLoading = true
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
    @State private var endDate = Date()

    private var startDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: startDate)
    }

    private var endDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: endDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateRangePicker
                billingContent
            }
            .navigationTitle("Pre-Billing")
            .refreshable { loadData() }
            .task { loadData() }
        }
    }

    // MARK: - Date Range Picker

    private var dateRangePicker: some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: startDate) { loadData() }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            DatePicker("To", selection: $endDate, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: endDate) { loadData() }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Billing Content

    @ViewBuilder
    private var billingContent: some View {
        if isLoading {
            ProgressView("Loading pre-billing data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Billing Data", systemImage: "doc.text")
            } description: {
                Text("No labor entries found for the selected period.")
            }
        } else {
            List {
                Section {
                    HStack(spacing: 16) {
                        summaryCard(title: "Jobs", value: "\(rows.count)", color: .blue)
                        summaryCard(title: "Reg Hrs", value: String(format: "%.1f", totalRegular), color: .green)
                        summaryCard(title: "OT Hrs", value: String(format: "%.1f", totalOvertime), color: .orange)
                    }
                    .padding(.vertical, 4)
                }

                Section("Job Summaries") {
                    ForEach(rows) { row in
                        billingRow(row)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Summary Card

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Billing Row

    private func billingRow(_ row: PreBillingRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.jobName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label(String(format: "%.1f reg", row.regularHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.overtimeHours > 0 {
                        Label(String(format: "%.1f OT", row.overtimeHours), systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f", row.regularHours + row.overtimeHours))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("total hrs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var totalRegular: Double { rows.reduce(0) { $0 + $1.regularHours } }
    private var totalOvertime: Double { rows.reduce(0) { $0 + $1.overtimeHours } }

    // MARK: - Data Model

    struct PreBillingRow: Identifiable {
        let id: Int64
        let jobName: String
        let regularHours: Double
        let overtimeHours: Double
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = rows.isEmpty
        do {
            rows = try db.writer.read { db in
                let sql = """
                    SELECT j.id, j.name AS job_name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours
                    FROM jobs j
                    LEFT JOIN labor_entries le ON le.job_id = j.id
                        AND le.work_date >= ? AND le.work_date <= ?
                    GROUP BY j.id
                    HAVING regular_hours > 0 OR overtime_hours > 0
                    ORDER BY j.name
                    """
                return try Row.fetchAll(db, sql: sql, arguments: [startDateString, endDateString]).map { row in
                    PreBillingRow(
                        id: row["id"],
                        jobName: row["job_name"],
                        regularHours: row["regular_hours"],
                        overtimeHours: row["overtime_hours"]
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSPreBillingPage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
