import SwiftUI
import WiredPartCore

/// Weekly availability grid page for iOS.
///
/// Displays employee rows with day-of-week availability indicators
/// adapted for mobile. Each employee row shows their name and colored
/// dots for each day of the week (Mon-Sun). Data is loaded via
/// `SchedulingService`. Supports week navigation and pull-to-refresh.
struct IOSWeeklyAvailabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [SchedulingService.WeeklyAvailabilityRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var weekOffset = 0
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Weekly Availability Help", sections: [
                ("What This Page Does", "The Weekly Availability page shows a grid of all employees and their availability for each day of the week. Green dots mean the person is available that day; red dots mean they are not."),
                ("How to Use It", "Navigate between weeks using the left and right arrows. The grid shows Monday through Sunday columns. Each employee row has colored dots indicating their availability for each day. Pull down to refresh."),
                ("Reading the Grid", "Green dot means the employee is available to work that day. Red dot means they are unavailable, whether due to time off, personal schedule, or other reasons."),
                ("Tips", "Use this view when planning the dispatch board to quickly see who is free each day. Cross-reference with the Dispatch Board to make sure you are not assigning people on their days off.")
            ])
        }
        .searchable(text: $searchText, prompt: "Search employees...")
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

    // MARK: - Filtered Data

    private var filteredRows: [SchedulingService.WeeklyAvailabilityRow] {
        if searchText.isEmpty { return rows }
        return rows.filter {
            $0.employeeName.localizedCaseInsensitiveContains(searchText)
        }
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
                    ForEach(filteredRows) { row in
                        availabilityRow(row)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Row

    private func availabilityRow(_ row: SchedulingService.WeeklyAvailabilityRow) -> some View {
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

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = rows.isEmpty
        loadError = nil
        do {
            rows = try service.getWeeklyAvailability(weekStartDate: weekStart)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
