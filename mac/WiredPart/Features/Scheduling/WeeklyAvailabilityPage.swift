import SwiftUI
import GRDB
import WiredPartCore

/// Weekly availability page — shows which employees are available each day
/// of the selected week. Helps dispatchers plan assignments.
///
/// Reads from the `schedules` and `time_off_requests` tables to build
/// a per-day availability grid for all active employees.
struct WeeklyAvailabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var employees: [AvailabilityEmployee] = []
    @State private var weekStart: Date = Calendar.current.startOfWeek(for: Date())
    @State private var isLoading = true

    private var weekDates: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading availability…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if employees.isEmpty {
                emptyState
            } else {
                availabilityGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .onChange(of: weekStart) { _, _ in loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Availability")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(weekRangeString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.left")
                }
                Button("This Week") {
                    weekStart = Calendar.current.startOfWeek(for: Date())
                }
                .buttonStyle(.bordered)
                Button {
                    weekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.right")
                }
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    private var weekRangeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let start = formatter.string(from: weekStart)
        let end = formatter.string(from: weekDates.last ?? weekStart)
        return "\(start) – \(end)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Employees Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add employees in the People section to see availability.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Availability Grid

    private var availabilityGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Day headers
                HStack(spacing: 0) {
                    Text("Employee")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 160, alignment: .leading)
                        .padding(.horizontal, 12)

                    ForEach(weekDates, id: \.self) { date in
                        Text(dayHeader(date))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Calendar.current.isDateInToday(date) ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))

                Divider()

                // Employee rows
                ForEach(employees) { employee in
                    HStack(spacing: 0) {
                        Text(employee.name)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                            .padding(.horizontal, 12)

                        ForEach(weekDates, id: \.self) { date in
                            let dateStr = isoDate(date)
                            let status = employee.dayStatuses[dateStr] ?? .available
                            availabilityCell(status)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    private func availabilityCell(_ status: DayStatus) -> some View {
        let (icon, color): (String, Color) = switch status {
        case .available: ("checkmark.circle.fill", .green)
        case .scheduled: ("calendar.badge.clock", .blue)
        case .timeOff: ("airplane.departure", .orange)
        case .unavailable: ("xmark.circle.fill", .red)
        }
        return Image(systemName: icon)
            .foregroundStyle(color)
            .font(.body)
    }

    private func dayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE\nM/d"
        return formatter.string(from: date)
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let startStr = isoDate(weekStart)
        let endStr = isoDate(weekDates.last ?? weekStart)

        do {
            try db.writer.read { dbConn in
                // Get all active employees
                let userRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT id, display_name FROM users
                        WHERE is_active = 1 AND deleted_at IS NULL
                        ORDER BY display_name ASC
                        """
                )

                // Get schedule entries for the week
                let scheduleRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT user_id, date FROM schedules
                        WHERE date >= ? AND date <= ? AND deleted_at IS NULL
                        """,
                    arguments: [startStr, endStr]
                )

                // Get time-off requests overlapping the week
                let timeOffRows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT user_id, start_date, end_date FROM time_off_requests
                        WHERE status = 'approved'
                          AND start_date <= ? AND end_date >= ?
                          AND deleted_at IS NULL
                        """,
                    arguments: [endStr, startStr]
                )

                // Build schedule lookup: userId -> Set<dateString>
                var scheduledDays: [Int64: Set<String>] = [:]
                for row in scheduleRows {
                    let uid: Int64 = row["user_id"] ?? 0
                    let date: String = row["date"] ?? ""
                    scheduledDays[uid, default: []].insert(date)
                }

                // Build time-off lookup: userId -> Set<dateString>
                var timeOffDays: [Int64: Set<String>] = [:]
                for row in timeOffRows {
                    let uid: Int64 = row["user_id"] ?? 0
                    let start: String = row["start_date"] ?? ""
                    let end: String = row["end_date"] ?? ""
                    // Add all dates in the range that fall within our week
                    for dateVal in weekDates {
                        let ds = isoDate(dateVal)
                        if ds >= start && ds <= end {
                            timeOffDays[uid, default: []].insert(ds)
                        }
                    }
                }

                // Build employee availability
                employees = userRows.map { row in
                    let uid: Int64 = row["id"] ?? 0
                    let name: String = row["display_name"] ?? "Unknown"
                    var dayStatuses: [String: DayStatus] = [:]

                    for date in weekDates {
                        let ds = isoDate(date)
                        if timeOffDays[uid]?.contains(ds) == true {
                            dayStatuses[ds] = .timeOff
                        } else if scheduledDays[uid]?.contains(ds) == true {
                            dayStatuses[ds] = .scheduled
                        } else {
                            dayStatuses[ds] = .available
                        }
                    }

                    return AvailabilityEmployee(id: uid, name: name, dayStatuses: dayStatuses)
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[WeeklyAvailabilityPage] Error: \(error)")
            }
            employees = []
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct AvailabilityEmployee: Identifiable {
    let id: Int64
    let name: String
    let dayStatuses: [String: DayStatus]
}

private enum DayStatus {
    case available
    case scheduled
    case timeOff
    case unavailable
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
