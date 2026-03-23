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
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
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

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else { return }
        isLoading = rows.isEmpty
        loadError = nil
        do {
            rows = try service.getSubSchedule(date: dateString)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
