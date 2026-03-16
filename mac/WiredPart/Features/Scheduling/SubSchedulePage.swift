import SwiftUI
import GRDB
import WiredPartCore

/// Subcontractor scheduling page — manages schedules for subcontractors
/// assigned to jobs. Shows who is scheduled where and when.
///
/// Subcontractors are users with the `subcontractor` role or contacts
/// flagged as subcontractors. Their schedule entries link to specific jobs.
struct SubSchedulePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var entries: [SubScheduleEntry] = []
    @State private var selectedDate: Date = Date()
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [SubScheduleEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.subcontractorName.lowercased().contains(query) ||
            $0.jobName.lowercased().contains(query) ||
            $0.company.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading sub schedules…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyState
            } else {
                scheduleTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Subcontractor Schedule")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(entries.count) assignment\(entries.count == 1 ? "" : "s") for selected period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                DatePicker("Week of:", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 140)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Subcontractor Schedules")
                .font(.title3)
                .fontWeight(.semibold)
            Text(searchText.isEmpty
                 ? "No subcontractors are scheduled for this period."
                 : "No schedules match your search.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table

    private var scheduleTable: some View {
        Table(filtered) {
            TableColumn("Subcontractor") { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.subcontractorName)
                        .fontWeight(.medium)
                    if !entry.company.isEmpty {
                        Text(entry.company)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 140, ideal: 180)

            TableColumn("Job") { entry in
                Text(entry.jobName)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Date") { entry in
                Text(String(entry.date.prefix(10)))
            }
            .width(90)

            TableColumn("Time") { entry in
                if let start = entry.startTime, let end = entry.endTime {
                    Text("\(start) – \(end)")
                        .font(.callout)
                } else {
                    Text("All Day")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("Status") { entry in
                statusBadge(entry.status)
            }
            .width(80)

            TableColumn("Notes") { entry in
                Text(entry.notes ?? "—")
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status.lowercased() {
        case "confirmed": .green
        case "pending": .orange
        case "cancelled": .red
        case "completed": .blue
        default: .gray
        }
        return Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        // Calculate week bounds from selectedDate
        let calendar = Calendar.current
        let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        let startDate = calendar.date(from: weekStart) ?? selectedDate
        let endDate = calendar.date(byAdding: .day, value: 6, to: startDate) ?? selectedDate

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        do {
            try db.writer.read { dbConn in
                let sql = """
                    SELECT s.id, s.date, s.start_time, s.end_time, s.status, s.notes,
                           COALESCE(u.display_name, u.email, 'Unknown') AS sub_name,
                           COALESCE(c.company_name, '') AS company,
                           COALESCE(j.job_name, 'Unassigned') AS job_name
                    FROM schedules s
                    LEFT JOIN users u ON u.id = s.user_id
                    LEFT JOIN contacts c ON c.user_id = s.user_id
                    LEFT JOIN jobs j ON j.id = s.job_id
                    WHERE s.date >= ? AND s.date <= ?
                      AND s.deleted_at IS NULL
                      AND (u.role = 'subcontractor' OR s.schedule_type = 'subcontractor')
                    ORDER BY s.date ASC, sub_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startStr, endStr])
                entries = rows.map { row in
                    SubScheduleEntry(
                        id: row["id"] ?? 0,
                        subcontractorName: row["sub_name"] ?? "Unknown",
                        company: row["company"] ?? "",
                        jobName: row["job_name"] ?? "Unassigned",
                        date: row["date"] ?? "",
                        startTime: row["start_time"] as String?,
                        endTime: row["end_time"] as String?,
                        status: row["status"] ?? "pending",
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[SubSchedulePage] Error: \(error)")
            }
            entries = []
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct SubScheduleEntry: Identifiable {
    let id: Int64
    let subcontractorName: String
    let company: String
    let jobName: String
    let date: String
    let startTime: String?
    let endTime: String?
    let status: String
    let notes: String?
}
