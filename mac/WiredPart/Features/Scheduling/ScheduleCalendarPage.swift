import SwiftUI
import WiredPartCore

/// Schedule calendar page showing the current user's schedule entries.
///
/// Displays a searchable, date-filtered table of schedule entries with
/// job name, date, start/end times, status, and notes columns.
/// Uses a date picker in the toolbar to navigate between dates.
struct ScheduleCalendarPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var entries: [SchedulingService.ScheduleEntry] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var selectedDate = Date()

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\SchedulingService.ScheduleEntry.date)]

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
                Text("Schedule")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies") for selected date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: selectedDate) { loadData() }

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading schedule...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No schedule entries")
                    .font(.headline)
                Text("No entries found for the selected date.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedEntries, sortOrder: $sortOrder) {
                TableColumn("Job Name", value: \.jobName) { entry in
                    Text(entry.jobName)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Date", value: \.date) { entry in
                    Text(entry.date)
                        .font(.callout)
                }
                .width(min: 90, ideal: 110)

                TableColumn("Start Time") { (entry: SchedulingService.ScheduleEntry) in
                    Text(entry.startTime ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("End Time") { (entry: SchedulingService.ScheduleEntry) in
                    Text(entry.endTime ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Status", value: \.status) { entry in
                    statusBadge(entry.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Notes") { (entry: SchedulingService.ScheduleEntry) in
                    Text(entry.notes ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 100, ideal: 180)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedEntries: [SchedulingService.ScheduleEntry] {
        entries.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "scheduled": .blue
        case "confirmed": .green
        case "in_progress": .orange
        case "completed": .purple
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: selectedDate)

        let userId = appCore.currentUser?.id ?? 0

        do {
            let service = SchedulingService(db: db)
            entries = try service.getMySchedule(
                userId: userId,
                startDate: dateStr,
                endDate: dateStr
            )
        } catch {
            print("[ScheduleCalendarPage] Load error: \(error)")
        }

        isLoading = false
    }
}
