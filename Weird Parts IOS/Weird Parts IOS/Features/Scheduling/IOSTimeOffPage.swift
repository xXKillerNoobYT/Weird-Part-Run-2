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
    @State private var allRequests: [SchedulingService.TimeOffRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var statusFilter = "all"
    private enum ActiveSheet: String, Identifiable {
        case requestTimeOff
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var actionError: String?

    private let statusOptions = ["all", "pending", "approved", "denied", "cancelled"]

    // Date filter
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "scheduling-time-off")
            statusPicker
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            timeOffContent
        }
        .task { appCore.onboardingManager?.markCompleted("timeoff-view") }
            .navigationTitle("Time Off")
            .searchable(text: $searchText, prompt: "Search requests...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .requestTimeOff } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Request time off")
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
                case .requestTimeOff:
                    RequestTimeOffSheet(onSave: { loadData() })
                        .environmentObject(appCore)
                case .help:
                    PageHelpSheet(title: "Time Off Help", sections: [
                        ("What This Page Does", "The Time Off page displays all time-off requests from employees. Each request shows the employee name, date range, reason, and approval status. Managers can approve or deny pending requests directly from this list."),
                        ("How to Use It", "Browse the list to see all requests. Use the search bar to filter by employee name or reason. Tap the + button to submit a new time-off request. If you have scheduling permissions, Approve and Deny buttons appear on pending requests."),
                        ("Status Meanings", "Orange 'Pending' means the request is awaiting manager review. Green 'Approved' means it has been granted. Red 'Denied' means it was rejected. Gray 'Cancelled' means the employee withdrew their request."),
                        ("Tips", "Approved time-off shows as red dots on the Schedule Calendar and triggers conflict warnings on the Dispatch Board. Always check the dispatch board after approving time off to reassign affected jobs.")
                    ])
                }
            }
            .alert("Error", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .refreshable { loadData() }
            .task { loadData() }
            .onAppear {
                // Register AI filter (prompt 62S)
                appCore.aiFilterRegistry.register(
                    pageId: "time-off",
                    filterName: "Time Off Status",
                    options: statusOptions,
                    activate: { value in
                        statusFilter = value
                        loadData()
                    }
                )
                appCore.aiFilterRegistry.applyPendingFilter(pageId: "time-off")
            }
            .onDisappear {
                appCore.aiFilterRegistry.deregister(pageId: "time-off")
            }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
    }

    // MARK: - Status Picker

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allRequests.count }
        return allRequests.filter { $0.status == status }.count
    }

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    SmartFilterCard(
                        title: status == "all" ? "All" : status.capitalized,
                        count: countForStatus(status),
                        isSelected: statusFilter == status
                    ) {
                        statusFilter = status
                        loadData()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var timeOffContent: some View {
        if isLoading {
            ProgressView("Loading time-off requests...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
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
            .listStyle(.insetGrouped)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)
                    .accessibilityHidden(true)

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
                                .accessibilityHidden(true)
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

            if appCore.hasPermission("manage_scheduling") && request.status == "pending" {
                HStack(spacing: 12) {
                    Spacer()
                    Button {
                        denyTimeOff(requestId: request.id)
                    } label: {
                        Label("Deny", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button {
                        approveTimeOff(requestId: request.id)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
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

    // MARK: - Actions

    private func approveTimeOff(requestId: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.updateTimeOffStatus(
                id: requestId,
                status: "approved",
                approvedBy: appCore.currentUser?.id
            )
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func denyTimeOff(requestId: Int64) {
        guard let service = appCore.schedulingService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.updateTimeOffStatus(
                id: requestId,
                status: "denied",
                approvedBy: appCore.currentUser?.id
            )
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
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
            allRequests = try service.listTimeOffRequests()
            requests = statusFilter == "all"
                ? allRequests
                : allRequests.filter { $0.status == statusFilter }
        } catch {
            loadError = userFriendlyError(error, context: "load time off data")
        }
        isLoading = false
    }
}
