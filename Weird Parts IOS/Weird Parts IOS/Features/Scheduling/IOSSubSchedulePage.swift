import SwiftUI
import GRDB
import WiredPartCore

/// Subcontractor schedule list page for iOS.
///
/// Displays a date-picker-driven list of subcontractor assignments
/// showing sub name, company, job, date, and status. Uses direct SQL
/// queries against the subcontractor_schedules, subcontractors, and
/// jobs tables. Supports date navigation and pull-to-refresh.
struct IOSSubSchedulePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [SubScheduleRow] = []
    @State private var isLoading = true
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
            scheduleContent
        }
        .navigationTitle("Sub Schedule")
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
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var scheduleContent: some View {
        if isLoading {
            ProgressView("Loading sub schedule...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Subs Scheduled", systemImage: "person.badge.clock")
            } description: {
                Text("No subcontractors scheduled for \(displayDate).")
            }
        } else {
            List(rows) { row in
                subRow(row)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Row

    private func subRow(_ row: SubScheduleRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.subName)
                    .fontWeight(.medium)
                if !row.companyName.isEmpty {
                    Label(row.companyName, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(row.jobName, systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(formatDate(row.scheduleDate), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            statusBadge(row.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "confirmed": .green
        case "pending": .orange
        case "cancelled": .red
        case "completed": .blue
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let date = f.date(from: String(dateString.prefix(10))) {
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: date)
        }
        return String(dateString.prefix(10))
    }

    // MARK: - Data Model

    struct SubScheduleRow: Identifiable {
        let id: Int64
        let subName: String
        let companyName: String
        let jobName: String
        let scheduleDate: String
        let status: String
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = rows.isEmpty
        do {
            rows = try db.writer.read { db in
                let sql = """
                    SELECT ss.id,
                           COALESCE(gc.contact_name, gc.company_name, 'Unknown') AS sub_name,
                           COALESCE(gc.company_name, '') AS company_name,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           ss.scheduled_date AS schedule_date,
                           COALESCE(ss.status, 'scheduled') AS status
                    FROM subcontractor_schedules ss
                    LEFT JOIN general_contractors gc ON gc.id = ss.gc_id
                    LEFT JOIN jobs j ON j.id = ss.job_id
                    WHERE ss.scheduled_date = ?
                    ORDER BY sub_name
                    """
                return try Row.fetchAll(db, sql: sql, arguments: [dateString]).map { row in
                    SubScheduleRow(
                        id: row["id"],
                        subName: row["sub_name"],
                        companyName: row["company_name"],
                        jobName: row["job_name"],
                        scheduleDate: row["schedule_date"],
                        status: row["status"]
                    )
                }
            }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSSubSchedulePage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
