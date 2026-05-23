import SwiftUI
import WiredPartCore

/// Subcontractor schedule list page for iOS.
///
/// Displays a date-picker-driven list of subcontractor assignments
/// showing sub name, company, job, date, and status. Data is loaded
/// via `SchedulingService`. Supports date navigation and pull-to-refresh.
struct IOSSubSchedulePage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [SchedulingService.SubScheduleRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedDate = Date()
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(SchedulingService.SubScheduleRow)
        case help
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let row): return "edit-\(row.id)"
            case .help: return "help"
            }
        }
    }

    private var dateString: String {
        Formatters.localDateFormatter.string(from: selectedDate)
    }

    private var displayDate: String {
        Formatters.dateFormatter.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            dateNavigator
            scheduleContent
        }
        .navigationTitle("Sub Schedule")
        .searchable(text: $searchText, prompt: "Search subs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .create } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add subcontractor schedule")
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
            case .create:
                CreateSubcontractorScheduleSheet(initialDate: selectedDate, onSave: { loadData() })
                    .environmentObject(appCore)
            case .edit(let row):
                CreateSubcontractorScheduleSheet(initialDate: selectedDate, existing: row, onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(title: "Sub Schedule Help", sections: [
                    ("What This Page Does", "The Sub Schedule page shows all subcontractor assignments for a given date, including exact scheduled arrival date plus optional arrival/departure times, scope of work, and notes when recorded."),
                    ("How to Use It", "Use the + button to add the date a subcontractor will show up. Use the date picker or arrow buttons to navigate between days. Tap a row to edit its scheduled date, times, scope, status, or notes."),
                    ("Status Badges", "Green 'Confirmed' means the sub has acknowledged the assignment. Orange 'Pending' means they have not confirmed yet. Blue 'Completed' means the work is done. Red 'Cancelled' means the assignment was removed."),
                    ("Tips", "Check this page each morning to confirm all subs are accounted for. Follow up on any 'Pending' status items to make sure subs know where to go.")
                ])
            }
        }
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
            .accessibilityLabel("Previous day")

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
            .accessibilityLabel("Next day")
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
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if rows.isEmpty {
            EmptyStateView(
                icon: "person.badge.clock",
                title: "No Subs Scheduled",
                message: "No subcontractors scheduled for \(displayDate)."
            )
        } else {
            List(rows) { row in
                subRow(row)
                    .contentShape(Rectangle())
                    .onTapGesture { activeSheet = .edit(row) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit") { activeSheet = .edit(row) }
                            .tint(.blue)
                    }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Row

    private func subRow(_ row: SchedulingService.SubScheduleRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)

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
                if let timeSummary = subTimeSummary(row) {
                    Label(timeSummary, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let scope = row.scopeOfWork, !scope.isEmpty {
                    Label(scope, systemImage: "list.clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let notes = row.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
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
        guard let date = Formatters.localDateFormatter.date(from: String(dateString.prefix(10))) else {
            return String(dateString.prefix(10))
        }
        return Formatters.shortDateDisplayFormatter.string(from: date)
    }

    private func subTimeSummary(_ row: SchedulingService.SubScheduleRow) -> String? {
        let arrival = row.arrivalTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let departure = row.departureTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !arrival.isEmpty && !departure.isEmpty { return "\(arrival) - \(departure)" }
        if !arrival.isEmpty { return "Arrives \(arrival)" }
        if !departure.isEmpty { return "Leaves \(departure)" }
        return nil
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
            rows = try service.getSubSchedule(date: dateString)
        } catch {
            loadError = userFriendlyError(error, context: "load sub schedule")
        }
        isLoading = false
    }
}
