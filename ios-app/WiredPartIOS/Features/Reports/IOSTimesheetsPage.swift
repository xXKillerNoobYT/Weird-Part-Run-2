import SwiftUI
import WiredPartCore

/// Timesheets report page for iOS.
///
/// Displays a list of timesheet rows aggregated per user within the
/// selected date range. Shows name, regular hours, overtime hours,
/// total hours, and days worked. Supports pull-to-refresh, search
/// filtering, and date range selection.
struct IOSTimesheetsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [ReportsService.TimesheetRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
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
                timesheetList
            }
            .navigationTitle("Timesheets")
            .searchable(text: $searchText, prompt: "Search employees...")
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

    // MARK: - Timesheet List

    @ViewBuilder
    private var timesheetList: some View {
        if isLoading {
            ProgressView("Loading timesheets...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRows.isEmpty {
            ContentUnavailableView {
                Label("No Timesheets", systemImage: "clock")
            } description: {
                Text("No timesheet data found for the selected period.")
            }
        } else {
            List(filteredRows, id: \.id) { row in
                timesheetRow(row)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredRows: [ReportsService.TimesheetRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.lowercased()
        return rows.filter {
            $0.userName.lowercased().contains(query)
        }
    }

    private func timesheetRow(_ row: ReportsService.TimesheetRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.userName)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Label(String(format: "%.1f", row.regularHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.overtimeHours > 0 {
                        Label(String(format: "%.1f OT", row.overtimeHours), systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Label("\(row.daysWorked) days worked", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f", row.totalHours))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("total hrs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else { return }
        isLoading = rows.isEmpty
        do {
            rows = try service.getTimesheetData(
                startDate: startDateString,
                endDate: endDateString
            )
        } catch {
            print("[IOSTimesheetsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
