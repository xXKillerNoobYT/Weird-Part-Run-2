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
    @State private var dateRange: ReportDateRange = .thisPeriod
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? startDate }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? endDate }

    private var startDateString: String {
        Formatters.localDateFormatter.string(from: effectiveStart)
    }

    private var endDateString: String {
        Formatters.localDateFormatter.string(from: effectiveEnd)
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $startDate, customEnd: $endDate)
            billingContent
        }
        .navigationTitle("Pre-Billing")
        .reportExportToolbar(
            title: "Pre-Billing",
            columns: ["Job", "Job Number", "Regular Hrs", "Overtime Hrs", "Material Cost", "Billable Amount", "Sources"],
            rows: filteredRows.map {
                [
                    $0.jobName,
                    $0.jobNumber,
                    String(format: "%.1f", $0.regularHours),
                    String(format: "%.1f", $0.overtimeHours),
                    formatCurrency($0.materialCost),
                    formatCurrency($0.billableAmount),
                    $0.sourceSummary
                ]
            }
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
            PageHelpSheet(title: "Pre-Billing Help", sections: [
                ("What This Page Does", "Summarizes labor hours per job for the selected date range so you can review them before sending invoices. Shows regular and overtime hours side by side for each job."),
                ("How to Use It", "Set the start and end dates to match your billing period. Review each job's hours. The top cards show totals across all jobs. Use the export button to generate a PDF or CSV for your billing workflow."),
                ("Tips", "Run this report before finalizing invoices. Compare the totals here against your job estimates to catch any billing surprises early. If hours look wrong, check the Timesheets page for details.")
            ])
        }
        .searchable(text: $searchText, prompt: "Search jobs...")
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear { postPageContext() }
        .onChange(of: searchText) { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsPrebillingPageInactive, object: nil)
        }
        .onChange(of: dateRange) { _, _ in loadData() }
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
            EmptyStateView(
                icon: "doc.text",
                title: "No Billing Data",
                message: "No labor entries found for the selected period."
            )
        } else {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        summaryCard(title: "Jobs", value: "\(rows.count)", color: .blue)
                        summaryCard(title: "Reg Hrs", value: String(format: "%.1f", totalRegular), color: .green)
                        summaryCard(title: "OT Hrs", value: String(format: "%.1f", totalOvertime), color: .orange)
                        summaryCard(title: "Materials", value: formatCurrency(totalMaterialCost), color: .purple)
                        summaryCard(title: "Billable", value: formatCurrency(totalBillableAmount), color: .primary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Job Summaries") {
                    if filteredRows.isEmpty {
                        Text("No jobs match the current search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredRows) { row in
                            billingRow(row)
                        }
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
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                    .lineLimit(2)
                if !row.jobNumber.isEmpty {
                    Text(row.jobNumber)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if !row.sourceSummary.isEmpty {
                    Text(row.sourceSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
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
                if row.materialCost > 0 || row.billableAmount > 0 {
                    Text(formatCurrency(row.billableAmount))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("billable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preBillingAccessibilityLabel(row))
        .accessibilityIdentifier("pre-billing-row-\(row.jobNumber)")
    }

    // MARK: - Computed

    private var filteredRows: [ReportsService.PreBillingRow] {
        if searchText.isEmpty { return rows }
        return rows.filter {
            $0.jobName.localizedCaseInsensitiveContains(searchText) ||
            $0.jobNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalRegular: Double { rows.reduce(0) { $0 + $1.regularHours } }
    private var totalOvertime: Double { rows.reduce(0) { $0 + $1.overtimeHours } }
    private var totalMaterialCost: Double { rows.reduce(0) { $0 + $1.materialCost } }
    private var totalBillableAmount: Double { rows.reduce(0) { $0 + $1.billableAmount } }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrencyTwoDecimal(value)
    }

    private func preBillingAccessibilityLabel(_ row: ReportsService.PreBillingRow) -> String {
        let jobNumber = row.jobNumber.isEmpty ? "" : ", job number \(row.jobNumber)"
        return "\(row.jobName)\(jobNumber), \(String(format: "%.1f", row.regularHours)) regular hours, \(String(format: "%.1f", row.overtimeHours)) overtime hours, \(String(format: "%.1f", row.regularHours + row.overtimeHours)) total hours, \(formatCurrency(row.billableAmount)) billable."
    }

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
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let regularHours = rows.reduce(0) { $0 + $1.regularHours }
        let overtimeHours = rows.reduce(0) { $0 + $1.overtimeHours }
        NotificationCenter.default.post(
            name: .reportsPrebillingPageActive,
            object: nil,
            userInfo: [
                "context": "Pre-Billing Report: \(startDateString) to \(endDateString), \(rows.count) jobs, \(filteredRows.count) visible, \(String(format: "%.1f", regularHours)) regular hours, \(String(format: "%.1f", overtimeHours)) overtime."
            ]
        )
    }
}
