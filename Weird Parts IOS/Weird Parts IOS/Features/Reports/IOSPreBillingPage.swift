import SwiftUI
import WiredPartCore

/// Pre-billing review page for iOS.
///
/// Displays job summaries with regular hours, overtime hours, and totals
/// for the selected date range. Uses `ReportsService.getPreBillingData()`
/// for data access. Supports date range selection and pull-to-refresh.
struct IOSPreBillingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [ReportsService.PreBillingRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
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
        VStack(spacing: 0) {
            StandardFilterBar(startDate: $startDate, endDate: $endDate)
            billingContent
        }
        .navigationTitle("Pre-Billing")
        .reportExportToolbar(
            title: "Pre-Billing",
            columns: ["Job", "Regular Hrs", "Overtime Hrs"],
            rows: rows.map { [$0.jobName, String(format: "%.1f", $0.regularHours),
                              String(format: "%.1f", $0.overtimeHours)] }
        )
        .refreshable { loadData() }
        .task { loadData() }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    // MARK: - Billing Content

    @ViewBuilder
    private var billingContent: some View {
        if isLoading {
            ProgressView("Loading pre-billing data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
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
            .listStyle(.insetGrouped)
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

    private func billingRow(_ row: ReportsService.PreBillingRow) -> some View {
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

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service is not available."
            return
        }
        isLoading = rows.isEmpty
        loadError = nil
        do {
            rows = try service.getPreBillingData(
                startDate: startDateString,
                endDate: endDateString
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
