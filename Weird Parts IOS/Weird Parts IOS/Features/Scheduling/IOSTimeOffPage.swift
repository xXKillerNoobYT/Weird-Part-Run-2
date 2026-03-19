import SwiftUI
import WiredPartCore

/// Time-off requests list page for iOS.
///
/// Displays a searchable list of time-off requests showing employee name,
/// requested dates, reason, and status badge. Uses
/// `SchedulingService.listTimeOffRequests()` with pull-to-refresh.
struct IOSTimeOffPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var requests: [SchedulingService.TimeOffRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""

    var body: some View {
        timeOffContent
            .navigationTitle("Time Off")
            .searchable(text: $searchText, prompt: "Search requests...")
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var timeOffContent: some View {
        if isLoading {
            ProgressView("Loading time-off requests...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if filteredRequests.isEmpty {
            ContentUnavailableView {
                Label("No Requests", systemImage: "calendar.badge.clock")
            } description: {
                Text("No time-off requests found.")
            }
        } else {
            List(filteredRequests, id: \.id) { request in
                requestRow(request)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredRequests: [SchedulingService.TimeOffRow] {
        guard !searchText.isEmpty else { return requests }
        let query = searchText.lowercased()
        return requests.filter {
            $0.userName.lowercased().contains(query) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Row

    private func requestRow(_ request: SchedulingService.TimeOffRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(request.userName)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(formatDate(request.startDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if request.startDate != request.endDate {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(formatDate(request.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let reason = request.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge(request.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badge

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "approved": .green
        case "pending": .orange
        case "denied", "rejected": .red
        case "cancelled": .secondary
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
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service unavailable"
            return
        }
        isLoading = requests.isEmpty
        do {
            requests = try service.listTimeOffRequests()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
