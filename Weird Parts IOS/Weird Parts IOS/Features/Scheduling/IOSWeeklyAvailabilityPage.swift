import SwiftUI
import WiredPartCore

/// Rolling 14-day availability planning preview for iOS.
///
/// Displays employee rows with day-by-day availability indicators in two
/// readable seven-day bands. The preview defaults to local today through
/// today + 13 and reuses the existing weekly availability service twice so
/// the first slice stays frontend-focused.
struct IOSWeeklyAvailabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var weekOneRows: [SchedulingService.WeeklyAvailabilityRow] = []
    @State private var weekTwoRows: [SchedulingService.WeeklyAvailabilityRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var fourteenDayStart = Calendar.current.startOfDay(for: Date())
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private var calendar: Calendar { Calendar.current }

    private var fourteenDayEnd: Date {
        calendar.date(byAdding: .day, value: 13, to: fourteenDayStart) ?? fourteenDayStart
    }

    private var fourteenDayRangeLabel: String {
        "\(shortDate(fourteenDayStart)) - \(shortDate(fourteenDayEnd))"
    }

    private var hasAnyRows: Bool {
        !weekOneRows.isEmpty || !weekTwoRows.isEmpty
    }

    private var bodyRowsAreFilteredEmpty: Bool {
        hasAnyRows && filteredRows(weekOneRows).isEmpty && filteredRows(weekTwoRows).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            fourteenDayNavigator
            availabilityContent
        }
        .navigationTitle("Availability")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "14-Day Planning Preview Help", sections: [
                ("What This Page Does", "The Availability page shows a 14-day planning preview of employee capacity from the selected local start date through the next 13 days. Green checkmarks mean the person is available; muted slashes mean unavailable."),
                ("How to Use It", "Navigate with Previous 14 days, Today, and Next 14 days. Search filters employee rows across both seven-day bands without changing the selected planning range."),
                ("Reading the Grid", "Each band keeps seven day columns readable on iPhone. Today is outlined when visible and weekends have a subtle secondary tint, but availability is always shown with labels and symbols, not color alone."),
                ("Scheduling Model", "Use Calendar for assigned employee jobs; use Sub Schedule for contractor commitments. Availability answers who can work; Calendar answers where employees are dispatched; Sub Schedule answers which contractors are committed.")
            ])
        }
        .searchable(text: $searchText, prompt: "Search employees...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - 14-Day Navigator

    private var fourteenDayNavigator: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Planning Preview")
                        .font(.headline)
                    Text(fourteenDayRangeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        shiftFourteenDayRange(by: -14)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous 14 days")

                    Button("Today") {
                        fourteenDayStart = calendar.startOfDay(for: Date())
                        loadData()
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Jump to today")

                    Button {
                        shiftFourteenDayRange(by: 14)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next 14 days")
                }
            }

            Text("Use Calendar for assigned employee jobs; use Sub Schedule for contractor commitments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Availability is people capacity. Use Calendar for assigned employee jobs. Use Sub Schedule for contractor commitments.")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func shiftFourteenDayRange(by days: Int) {
        fourteenDayStart = calendar.date(byAdding: .day, value: days, to: fourteenDayStart) ?? fourteenDayStart
        loadData()
    }

    // MARK: - Filtered Data

    private func filteredRows(_ rows: [SchedulingService.WeeklyAvailabilityRow]) -> [SchedulingService.WeeklyAvailabilityRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.employeeName.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Content

    @ViewBuilder
    private var availabilityContent: some View {
        if isLoading {
            ProgressView("Loading 14-day planning preview...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if !hasAnyRows {
            EmptyStateView(
                icon: "calendar.badge.exclamationmark",
                title: "No Availability Data",
                message: "No availability data for \(fourteenDayRangeLabel)."
            )
        } else if bodyRowsAreFilteredEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Employees Match",
                message: "No employees match \"\(searchText)\".",
                actionLabel: "Clear Search",
                actionIcon: "xmark.circle"
            ) {
                searchText = ""
            }
        } else {
            List {
                weekBand(
                    title: "Week 1",
                    startDate: fourteenDayStart,
                    rows: filteredRows(weekOneRows)
                )

                weekBand(
                    title: "Week 2",
                    startDate: calendar.date(byAdding: .day, value: 7, to: fourteenDayStart) ?? fourteenDayStart,
                    rows: filteredRows(weekTwoRows)
                )
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Week Bands

    private func weekBand(title: String, startDate: Date, rows: [SchedulingService.WeeklyAvailabilityRow]) -> some View {
        let dates = sevenDates(startingAt: startDate)
        return Section {
            dayHeaderRow(dates: dates)
            ForEach(rows) { row in
                availabilityRow(row, dates: dates)
            }
        } header: {
            Text("\(title) · \(shortDate(startDate)) - \(shortDate(dates.last ?? startDate))")
        }
    }

    private func dayHeaderRow(dates: [Date]) -> some View {
        HStack(spacing: 0) {
            Text("Employee")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<7, id: \.self) { dayIndex in
                let date = dates[dayIndex]
                Text(dayColumnLabel(date))
                    .font(.system(.caption2, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 36)
                    .padding(.vertical, 4)
                    .background(dayHeaderBackground(date))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(todayOutline(date))
                    .foregroundStyle(isWeekend(date) ? Color.secondary : Color.primary)
                    .accessibilityLabel(dayAccessibilityLabel(date))
            }
        }
    }

    private func availabilityRow(_ row: SchedulingService.WeeklyAvailabilityRow, dates: [Date]) -> some View {
        let availableCount = row.days.prefix(7).filter { $0 }.count
        return HStack(spacing: 0) {
            Text(row.employeeName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<7, id: \.self) { dayIndex in
                let available = dayIndex < row.days.count && row.days[dayIndex]
                Image(systemName: available ? "checkmark.circle.fill" : "slash.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(available ? Color.green : Color.red.opacity(0.45))
                    .frame(width: 36, height: 30)
                    .background(isWeekend(dates[dayIndex]) ? Color.secondary.opacity(0.06) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(todayOutline(dates[dayIndex]))
                    .accessibilityLabel("\(row.employeeName), \(fullDate(dates[dayIndex])), \(available ? "available" : "unavailable")")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.employeeName): available \(availableCount) of next 7 days in this band")
    }

    // MARK: - Date Helpers

    private func sevenDates(startingAt startDate: Date) -> [Date] {
        (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date)
    }

    private func dayHeaderBackground(_ date: Date) -> Color {
        if isToday(date) { return Color.accentColor.opacity(0.14) }
        if isWeekend(date) { return Color.secondary.opacity(0.10) }
        return Color.clear
    }

    @ViewBuilder
    private func todayOutline(_ date: Date) -> some View {
        if isToday(date) {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.accentColor, lineWidth: 1.5)
        }
    }

    private func dayColumnLabel(_ date: Date) -> String {
        let weekday = DateFormatter()
        weekday.dateFormat = "E"
        let day = calendar.component(.day, from: date)
        return "\(weekday.string(from: date))\n\(day)"
    }

    private func dayAccessibilityLabel(_ date: Date) -> String {
        var label = fullDate(date)
        if isToday(date) { label += ", today" }
        if isWeekend(date) { label += ", weekend" }
        return label
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = !hasAnyRows
        loadError = nil
        do {
            let weekTwoStart = calendar.date(byAdding: .day, value: 7, to: fourteenDayStart) ?? fourteenDayStart
            weekOneRows = try service.getWeeklyAvailability(weekStartDate: fourteenDayStart)
            weekTwoRows = try service.getWeeklyAvailability(weekStartDate: weekTwoStart)
        } catch {
            loadError = userFriendlyError(error, context: "load 14-day planning preview")
        }
        isLoading = false
    }
}
