import SwiftUI
import WiredPartCore

/// Schedule calendar page for iOS.
///
/// Shows a week or month view of schedule entries. Month view shows
/// dots indicating AM/PM/Full-day assignments. Tapping a day shows
/// a detail section below the calendar. Supports half-day scheduling.
struct IOSScheduleCalendarPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Calendar Mode

    enum CalendarMode: String, CaseIterable {
        case twoWeeks = "14 Days"
        case week = "Week"
        case month = "Month"
    }

    // MARK: - State

    @State private var calendarMode: CalendarMode = .twoWeeks
    @State private var entries: [SchedulingService.ScheduleEntry] = []
    @State private var monthScheduleData: [String: SchedulingService.DayScheduleSummary] = [:]
    @State private var dayEntries: [SchedulingService.ScheduleEntry] = []
    @State private var timeOffEntries: [SchedulingService.TimeOffEntry] = []
    @State private var isLoading = true
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case createEntry
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private let calendar = Calendar.current

    /// The date range for the selected list mode.
    ///
    /// GH #610 asks for a rolling 14-day preview that starts on the selected
    /// day/current day, not the calendar week boundary. The old Week mode remains
    /// available for users who prefer Sunday/Monday week grouping.
    private var listRangeStartDate: Date {
        switch calendarMode {
        case .twoWeeks:
            calendar.startOfDay(for: selectedDate)
        case .week, .month:
            calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
        }
    }

    private var listRangeEndDate: Date {
        let days = calendarMode == .twoWeeks ? 13 : 6
        return calendar.date(byAdding: .day, value: days, to: listRangeStartDate) ?? listRangeStartDate
    }

    private var listRangeStart: String {
        Formatters.iso8601DateOnly.string(from: listRangeStartDate)
    }

    private var listRangeEnd: String {
        Formatters.iso8601DateOnly.string(from: listRangeEndDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "scheduling-calendar")
            SkippedModuleHint(moduleId: "scheduling")

            // Week/Month toggle
            Picker("View", selection: $calendarMode) {
                ForEach(CalendarMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: calendarMode) {
                loadData()
            }

            if calendarMode == .month {
                monthView
                dayDetailSection
            } else {
                listNavigator
                scheduleList
            }
        }
        .navigationTitle("My Schedule")
        .searchable(text: $searchText, prompt: "Search schedule...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createEntry } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add schedule entry")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createEntry:
                CreateScheduleEntrySheet(date: selectedDateString, onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(title: "Schedule Calendar Help", sections: [
                    ("What This Page Does", "The Schedule Calendar shows your work assignments in a rolling 14-day preview, a week list, or a month grid. Month view uses colored dots to indicate AM (blue), PM (green), full-day (orange), and time-off (red) entries for each day."),
                    ("How to Use It", "Use 14 Days for fast two-week planning from the selected date, Week for calendar-week grouping, or Month for the grid. In month view, tap any day to see its detail below the calendar. Use the + button to create a new schedule entry."),
                    ("Color Coding", "Blue dots and badges mean AM shifts, green means PM, orange means full day. Red dots indicate someone has time off that day."),
                    ("Tips", "Pull down to refresh the schedule. Use the search bar to filter entries by job name or notes. Navigate between 14-day windows, weeks, or months using the arrow buttons.")
                ])
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
        .task { appCore.onboardingManager?.markCompleted("schedule-view") }
        .onAppear {
            let dateStr = Formatters.iso8601DateOnly.string(from: selectedDate)
            NotificationCenter.default.post(
                name: .scheduleCalendarPageActive,
                object: nil,
                userInfo: [
                    "context": "Schedule Calendar: mode \(calendarMode.rawValue), selected date \(dateStr), \(entries.count) entries this week, \(timeOffEntries.count) time-off entries."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .scheduleCalendarPageInactive, object: nil)
        }
    }

    private var selectedDateString: String {
        Formatters.iso8601DateOnly.string(from: selectedDate)
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            // Month/year header with navigation
            HStack {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                        selectedDate = prev
                        loadData()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(.headline)

                Spacer()

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                        selectedDate = next
                        loadData()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next month")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // Day-of-week headers
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(daysInMonth(), id: \.self) { date in
                    let dateStr = Formatters.iso8601DateOnly.string(from: date)
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date),
                        isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month),
                        summary: monthScheduleData[dateStr]
                    )
                    .onTapGesture {
                        selectedDate = date
                        loadDayDetail()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Day Detail Section

    @ViewBuilder
    private var dayDetailSection: some View {
        let amEntries = dayEntries.filter { $0.timeSlot == "am" }
        let pmEntries = dayEntries.filter { $0.timeSlot == "pm" }
        let fullEntries = dayEntries.filter { $0.timeSlot == "full" }

        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dayEntries.isEmpty && timeOffEntries.isEmpty {
            VStack(spacing: 8) {
                Text(selectedDate, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                    .padding(.top, 12)
                Text("No schedule for this day")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month().day())
                        .font(.headline)
                        .listRowBackground(Color.clear)
                }

                // AM assignments
                if !amEntries.isEmpty {
                    Section("AM (\(amEntries.count))") {
                        ForEach(amEntries, id: \.id) { entry in
                            scheduleEntryRow(entry)
                        }
                    }
                }

                // PM assignments
                if !pmEntries.isEmpty {
                    Section("PM (\(pmEntries.count))") {
                        ForEach(pmEntries, id: \.id) { entry in
                            scheduleEntryRow(entry)
                        }
                    }
                }

                // Full day assignments
                if !fullEntries.isEmpty {
                    Section("Full Day (\(fullEntries.count))") {
                        ForEach(fullEntries, id: \.id) { entry in
                            scheduleEntryRow(entry)
                        }
                    }
                }

                // Time off
                if !timeOffEntries.isEmpty {
                    Section("Time Off (\(timeOffEntries.count))") {
                        ForEach(timeOffEntries, id: \.id) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "moon.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(entry.employeeName)
                                Spacer()
                                Text("Time Off")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func scheduleEntryRow(_ entry: SchedulingService.ScheduleEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = entry.userName {
                    Text(name)
                        .fontWeight(.medium)
                        .font(.subheadline)
                }
                Text(entry.jobName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let start = entry.startTime, !start.isEmpty {
                Text(start)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            statusBadge(entry.status)
        }
    }

    // MARK: - List View Navigator

    private var listNavigator: some View {
        let stepDays = calendarMode == .twoWeeks ? 14 : 7
        let previousLabel = calendarMode == .twoWeeks ? "Previous 14 days" : "Previous week"
        let nextLabel = calendarMode == .twoWeeks ? "Next 14 days" : "Next week"

        return HStack {
            Button {
                selectedDate = calendar.date(byAdding: .day, value: -stepDays, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(previousLabel)

            Spacer()

            VStack(spacing: 2) {
                Text(calendarMode == .twoWeeks ? "Next 14 Days" : "Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(listRangeStart) - \(listRangeEnd)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .day, value: stepDays, to: selectedDate) ?? selectedDate
                loadData()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(nextLabel)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Schedule List (week view)

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
                message: calendarMode == .twoWeeks ? "No schedule entries for the next 14 days." : "No schedule entries for this week."
            )
        } else {
            List(filteredEntries, id: \.id) { entry in
                weekScheduleRow(entry)
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

    private func weekScheduleRow(_ entry: SchedulingService.ScheduleEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.jobName)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(entry.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.timeSlot != "full" {
                        Text(entry.timeSlot.uppercased())
                            .font(.system(.caption2, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(entry.timeSlot == "am" ? Color.blue.opacity(0.15) : Color.green.opacity(0.15)))
                            .foregroundStyle(entry.timeSlot == "am" ? .blue : .green)
                    }
                }
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

    // MARK: - Calendar Helpers

    /// Compute the array of dates to display in the month grid (includes padding days).
    private func daysInMonth() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))
        else { return [] }

        // Find the weekday of the first day (0 = Sunday)
        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1

        // Start from the first visible day (may be in previous month)
        guard let gridStart = calendar.date(byAdding: .day, value: -firstWeekday, to: monthStart) else { return [] }

        // Calculate total cells needed (always show full weeks)
        let daysInMonth = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        let totalCells = ((firstWeekday + daysInMonth + 6) / 7) * 7

        return (0..<totalCells).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
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

        isLoading = true
        loadError = nil

        do {
            if calendarMode == .month {
                let year = calendar.component(.year, from: selectedDate)
                let month = calendar.component(.month, from: selectedDate)
                monthScheduleData = try service.getMonthScheduleSummary(year: year, month: month)
                loadDayDetail()
            } else {
                entries = try service.getMySchedule(
                    userId: userId,
                    startDate: listRangeStart,
                    endDate: listRangeEnd
                )
            }
        } catch {
            loadError = userFriendlyError(error, context: "load schedule")
        }
        isLoading = false
    }

    private func loadDayDetail() {
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            isLoading = false
            return
        }
        let dateStr = selectedDateString
        do {
            dayEntries = try service.getScheduleEntriesForDate(date: dateStr)
            timeOffEntries = try service.getTimeOffForDate(date: dateStr)
        } catch {
            dayEntries = []
            timeOffEntries = []
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let summary: SchedulingService.DayScheduleSummary?

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isCurrentMonth ? .primary : .tertiary)

            // Dots for scheduled work
            if let summary {
                HStack(spacing: 2) {
                    if summary.amCount > 0 {
                        Circle()
                            .fill(.blue)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Status: AM shift scheduled")
                    }
                    if summary.pmCount > 0 {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Status: PM shift scheduled")
                    }
                    if summary.fullDayCount > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Status: Full day scheduled")
                    }
                    if summary.timeOffCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 4, height: 4)
                            .accessibilityLabel("Status: Time off")
                    }
                }
            } else {
                // Spacer to keep consistent height
                HStack(spacing: 2) {
                    Circle()
                        .fill(.clear)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.2) : isToday ? Color.blue.opacity(0.05) : Color.clear)
        )
    }
}
