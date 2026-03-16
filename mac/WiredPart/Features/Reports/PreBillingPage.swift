import SwiftUI
import GRDB
import WiredPartCore

/// Pre-billing page — review labor hours per job before generating invoices.
///
/// Shows all active billing periods with their labor data. Office staff
/// reviews hours, makes adjustments, and locks periods for billing.
struct PreBillingPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var jobSummaries: [JobBillingSummary] = []
    @State private var startDate: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var endDate: Date = Date()
    @State private var isLoading = true
    @State private var totalRegular: Double = 0
    @State private var totalOvertime: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading billing data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if jobSummaries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    summaryCards
                    billingTable
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pre-Billing Review")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Review labor hours before billing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                DatePicker("From:", selection: $startDate, displayedComponents: .date)
                    .frame(width: 200)
                DatePicker("To:", selection: $endDate, displayedComponents: .date)
                    .frame(width: 200)
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "Total Regular",
                value: String(format: "%.1f hrs", totalRegular),
                icon: "clock",
                color: .blue
            )
            summaryCard(
                title: "Total Overtime",
                value: String(format: "%.1f hrs", totalOvertime),
                icon: "clock.badge.exclamationmark",
                color: .orange
            )
            summaryCard(
                title: "Total Hours",
                value: String(format: "%.1f hrs", totalRegular + totalOvertime),
                icon: "timer",
                color: .green
            )
            summaryCard(
                title: "Jobs",
                value: "\(jobSummaries.count)",
                icon: "hammer",
                color: .purple
            )
        }
        .padding()
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Labor Data")
                .font(.title3)
                .fontWeight(.semibold)
            Text("No labor entries found for the selected period.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Billing Table

    private var billingTable: some View {
        Table(jobSummaries) {
            TableColumn("Job") { summary in
                Text(summary.jobName)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Workers") { summary in
                Text("\(summary.workerCount)")
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Regular Hrs") { summary in
                Text(String(format: "%.1f", summary.regularHours))
                    .monospacedDigit()
            }
            .width(90)

            TableColumn("OT Hrs") { summary in
                Text(String(format: "%.1f", summary.overtimeHours))
                    .monospacedDigit()
                    .foregroundStyle(summary.overtimeHours > 0 ? .orange : .secondary)
            }
            .width(70)

            TableColumn("Total Hrs") { summary in
                Text(String(format: "%.1f", summary.totalHours))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(80)

            TableColumn("Status") { summary in
                Text(summary.jobStatus.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                    .foregroundStyle(.blue)
            }
            .width(90)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        do {
            try db.writer.read { dbConn in
                let sql = """
                    SELECT j.id, j.job_name, j.status AS job_status,
                           COUNT(DISTINCT le.user_id) AS worker_count,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours,
                           COALESCE(SUM(le.regular_hours), 0) + COALESCE(SUM(le.overtime_hours), 0) AS total_hours
                    FROM labor_entries le
                    JOIN jobs j ON j.id = le.job_id
                    WHERE le.deleted_at IS NULL
                      AND j.deleted_at IS NULL
                      AND date(le.clock_in) >= ?
                      AND date(le.clock_in) <= ?
                    GROUP BY j.id
                    ORDER BY total_hours DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startStr, endStr])
                jobSummaries = rows.map { row in
                    JobBillingSummary(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        jobStatus: row["job_status"] ?? "active",
                        workerCount: row["worker_count"] ?? 0,
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        totalHours: row["total_hours"] ?? 0.0
                    )
                }

                totalRegular = jobSummaries.reduce(0) { $0 + $1.regularHours }
                totalOvertime = jobSummaries.reduce(0) { $0 + $1.overtimeHours }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[PreBillingPage] Error: \(error)")
            }
            jobSummaries = []
            totalRegular = 0
            totalOvertime = 0
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct JobBillingSummary: Identifiable {
    let id: Int64
    let jobName: String
    let jobStatus: String
    let workerCount: Int
    let regularHours: Double
    let overtimeHours: Double
    let totalHours: Double
}
