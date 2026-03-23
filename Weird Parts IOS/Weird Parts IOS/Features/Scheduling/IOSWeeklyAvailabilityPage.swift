import SwiftUI
import GRDB
import WiredPartCore

/// Weekly availability grid page for iOS.
///
/// Displays employee rows with day-of-week availability indicators
/// adapted for mobile. Each employee row shows their name and colored
/// dots for each day of the week (Mon-Sun). Uses direct SQL queries
/// against the employee_availability table. Supports week navigation
/// and pull-to-refresh.
struct IOSWeeklyAvailabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [AvailabilityRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var weekOffset = 0

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var weekStart: Date {
        let cal = Calendar.current
        let today = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
    }

    private var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(f.string(from: weekStart)) - \(f.string(from: end))"
    }

    private var weekStartString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: weekStart)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekNavigator
            availabilityContent
        }
        .navigationTitle("Availability")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Week Navigator

    private var weekNavigator: some View {
        HStack {
            Button {
                weekOffset -= 1
                loadData()
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(weekLabel)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                weekOffset += 1
                loadData()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var availabilityContent: some View {
        if isLoading {
            ProgressView("Loading availability...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Data", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("No availability data for this week.")
            }
        } else {
            List {
                // Day header row
                Section {
                    HStack(spacing: 0) {
                        Text("Employee")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(.caption2, weight: .bold))
                                .frame(width: 30)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    ForEach(rows) { row in
                        availabilityRow(row)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Row

    private func availabilityRow(_ row: AvailabilityRow) -> some View {
        HStack(spacing: 0) {
            Text(row.employeeName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<7, id: \.self) { dayIndex in
                Circle()
                    .fill(dayIndex < row.days.count && row.days[dayIndex] ? Color.green : Color.red.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .frame(width: 30)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data Model

    struct AvailabilityRow: Identifiable {
        let id: Int64
        let employeeName: String
        let days: [Bool] // Mon-Sun, 7 entries
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = rows.isEmpty
        loadError = nil
        do {
            let weekDates = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let dateStrings = weekDates.map { f.string(from: $0) }

            rows = try db.writer.read { db in
                let empSql = "SELECT id, COALESCE(display_name, email) AS name FROM users WHERE deleted_at IS NULL ORDER BY name"
                let employees = try Row.fetchAll(db, sql: empSql)

                return try employees.map { emp in
                    let empId: Int64 = emp["id"]
                    let name: String = emp["name"]

                    // Check schedule_exceptions for days off (absence = not available)
                    let days = try dateStrings.map { dateStr -> Bool in
                        let countSql = "SELECT COUNT(*) FROM schedule_exceptions WHERE user_id = ? AND exception_date = ? AND deleted_at IS NULL"
                        let count = try Int.fetchOne(db, sql: countSql, arguments: [empId, dateStr]) ?? 0
                        return count == 0  // Available if no exception for that date
                    }

                    return AvailabilityRow(id: empId, employeeName: name, days: days)
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                loadError = error.localizedDescription
            }
        }
        isLoading = false
    }
}
