import SwiftUI
import WiredPartCore

/// Dispatch board page showing who is dispatched where on a given date.
///
/// Displays a table of dispatch entries with user name, job name, vehicle,
/// status, and notes columns. Uses a date picker in the toolbar to navigate
/// between dates.
struct DispatchBoardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var dispatches: [SchedulingService.DispatchRow] = []
    @State private var isLoading = true

    // MARK: - Filters

    @State private var selectedDate = Date()

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\SchedulingService.DispatchRow.userName)]

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
                Text("Dispatch Board")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(dispatches.count) dispatch\(dispatches.count == 1 ? "" : "es") for selected date")
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
            ProgressView("Loading dispatch board...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dispatches.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No dispatches")
                    .font(.headline)
                Text("No dispatch entries found for the selected date.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedDispatches, sortOrder: $sortOrder) {
                TableColumn("User", value: \.userName) { row in
                    Text(row.userName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Job", value: \.jobName) { row in
                    Text(row.jobName)
                        .font(.callout)
                }
                .width(min: 120, ideal: 200)

                TableColumn("Vehicle") { (row: SchedulingService.DispatchRow) in
                    Text(row.vehicleName ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Status", value: \.status) { row in
                    statusBadge(row.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Notes") { (row: SchedulingService.DispatchRow) in
                    Text(row.notes ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 100, ideal: 180)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedDispatches: [SchedulingService.DispatchRow] {
        dispatches.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending": .orange
        case "dispatched": .blue
        case "en_route": .purple
        case "on_site": .green
        case "completed": .gray
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

        do {
            let service = SchedulingService(db: db)
            dispatches = try service.getDispatchBoard(date: dateStr)
        } catch {
            print("[DispatchBoardPage] Load error: \(error)")
        }

        isLoading = false
    }
}
