import SwiftUI
import WiredPartCore

/// Time-off requests page showing all requests with filtering by status.
///
/// Displays a table of time-off requests with user name, date range, reason,
/// status badge, and approver columns. Supports filtering by request status.
struct TimeOffPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var requests: [SchedulingService.TimeOffRow] = []
    @State private var isLoading = true
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\SchedulingService.TimeOffRow.startDate)]

    private let statusOptions = ["all", "pending", "approved", "denied", "cancelled"]

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
                Text("Time-Off Requests")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(requests.count) request\(requests.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { loadData() }

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
            ProgressView("Loading time-off requests...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if requests.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No time-off requests")
                    .font(.headline)
                Text("No requests found matching your filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedRequests, sortOrder: $sortOrder) {
                TableColumn("User", value: \.userName) { row in
                    Text(row.userName)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Start Date", value: \.startDate) { row in
                    Text(row.startDate)
                        .font(.callout)
                }
                .width(min: 90, ideal: 110)

                TableColumn("End Date", value: \.endDate) { row in
                    Text(row.endDate)
                        .font(.callout)
                }
                .width(min: 90, ideal: 110)

                TableColumn("Reason") { (row: SchedulingService.TimeOffRow) in
                    Text(row.reason ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 100, ideal: 180)

                TableColumn("Status", value: \.status) { row in
                    statusBadge(row.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Approved By") { (row: SchedulingService.TimeOffRow) in
                    Text(row.approvedByName ?? "-")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedRequests: [SchedulingService.TimeOffRow] {
        requests.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending": .orange
        case "approved": .green
        case "denied": .red
        case "cancelled": .gray
        default: .secondary
        }
        return Text(status.capitalized)
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

        do {
            let service = SchedulingService(db: db)
            requests = try service.listTimeOffRequests(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            print("[TimeOffPage] Load error: \(error)")
        }

        isLoading = false
    }
}
