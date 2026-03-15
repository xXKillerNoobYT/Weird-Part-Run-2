import SwiftUI
import WiredPartCore

/// Timesheets page showing aggregated labor hours per user within a date range.
///
/// Displays a table with user name, regular hours, overtime hours, total hours,
/// and days worked columns. Includes date range pickers in the toolbar defaulting
/// to the current month.
struct TimesheetsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var rows: [ReportsService.TimesheetRow] = []
    @State private var isLoading = true

    // MARK: - Filters (default: start of current month to today)

    @State private var startDate = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var endDate = Date()

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ReportsService.TimesheetRow.userName)]

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
                Text("Timesheets")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(rows.count) user\(rows.count == 1 ? "" : "s") · \(String(format: "%.1f", totalHours)) total hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("From")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .frame(width: 130)

                Text("To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .frame(width: 130)
            }
            .onChange(of: startDate) { loadData() }
            .onChange(of: endDate) { loadData() }

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
        rows.reduce(0) { $0 + $1.totalHours }
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading timesheet data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No timesheet data")
                    .font(.headline)
                Text("No labor entries found for the selected date range.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedRows, sortOrder: $sortOrder) {
                TableColumn("User", value: \.userName) { row in
                    Text(row.userName)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Regular Hours", value: \.regularHours) { row in
                    Text(String(format: "%.1f", row.regularHours))
                        .font(.callout)
                }
                .width(min: 90, ideal: 110)

                TableColumn("OT Hours", value: \.overtimeHours) { row in
                    Text(String(format: "%.1f", row.overtimeHours))
                        .font(.callout)
                        .foregroundStyle(row.overtimeHours > 0 ? .orange : .secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Total Hours", value: \.totalHours) { row in
                    Text(String(format: "%.1f", row.totalHours))
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Days Worked", value: \.daysWorked) { row in
                    Text("\(row.daysWorked)")
                        .font(.callout)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedRows: [ReportsService.TimesheetRow] {
        rows.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        do {
            let service = ReportsService(db: db)
            rows = try service.getTimesheetData(startDate: start, endDate: end)
        } catch {
            print("[TimesheetsPage] Load error: \(error)")
        }

        isLoading = false
    }
}
