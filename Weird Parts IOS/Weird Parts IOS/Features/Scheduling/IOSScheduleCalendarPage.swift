import SwiftUI
import WiredPartCore

/// Schedule calendar page for iOS.
///
/// Shows the current user's schedule entries for the selected week.
/// Each row displays job name, date, time range, and status.
/// Supports pull-to-refresh and week navigation.
struct IOSScheduleCalendarPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var entries: [SchedulingService.ScheduleEntry] = []
    @State private var isLoading = true
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case createEntry
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    /// The date range for the current week view.
    private var weekStartDate: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
    }

    private var weekStart: String {
        ISO8601DateFormatter.dateOnlyFormatter.string(from: weekStartDate)
    }

    private var weekEnd: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
        return ISO8601DateFormatter.dateOnlyFormatter.string(from: end)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekNavigator
            scheduleList
        }
        .navigationTitle("My Schedule")
        .searchable(text: $searchText, prompt: "Search schedule...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createEntry } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createEntry:
                CreateScheduleEntrySheet(date: weekStart, onSave: { loadData() })
                    .environmentObject(appCore)
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Week Navigator

    private var weekNavigator: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text("\(weekStart) - \(weekEnd)")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Schedule List

    @ViewBuilder
    private var scheduleList: some View {
        if isLoading {
            ProgressView("Loading schedule...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredEntries.isEmpty {
            EmptyStateView(
                icon: "calendar",
                title: "No Schedule",
                message: "No schedule entries for this week."
            )
        } else {
            List(filteredEntries, id: \.id) { entry in
                scheduleRow(entry)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredEntries: [SchedulingService.ScheduleEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.jobName.lowercased().contains(query) ||
            ($0.notes?.lowercased().contains(query) ?? false)
        }
    }

    private func scheduleRow(_ entry: SchedulingService.ScheduleEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.jobName)
                    .fontWeight(.medium)
                Text(entry.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let start = entry.startTime {
                        Text(start)
                            .font(.system(.caption, design: .monospaced))
                    }
                    if entry.startTime != nil, entry.endTime != nil {
                        Text("-")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let end = entry.endTime {
                        Text(end)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .foregroundStyle(.secondary)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge(entry.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "scheduled": .blue
        case "in_progress": .orange
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service is not available."
            return
        }
        guard let userId = appCore.currentUser?.id else {
            isLoading = false
            loadError = "No logged-in user found."
            return
        }
        isLoading = entries.isEmpty
        loadError = nil
        do {
            entries = try service.getMySchedule(
                userId: userId,
                startDate: weekStart,
                endDate: weekEnd
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Date Formatter Helper

private extension ISO8601DateFormatter {
    @MainActor
    static let dateOnlyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
