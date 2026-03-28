import SwiftUI
import WiredPartCore

/// Receiving incoming shipments page for iOS.
///
/// Shows active and recent receiving sessions for purchase orders.
/// Displays PO ID, started-by name, mode, status, and item count.
/// Supports pull-to-refresh, smart card filters by status,
/// start new session, and continue active sessions.
struct IOSReceivingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var sessions: [WarehouseService.ReceivingSessionInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedFilter: StatusFilter?

    private enum ActiveSheet: Identifiable {
        case startReceiving
        case continueSession(Int64)
        case help

        var id: String { String(describing: self) }
    }

    private enum StatusFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
        case cancelled = "Cancelled"

        var matchStatuses: [String] {
            switch self {
            case .active: ["in_progress", "active"]
            case .completed: ["completed"]
            case .cancelled: ["cancelled"]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-receiving")

            // Smart card filters
            if !sessions.isEmpty {
                smartCardFilters
            }

            sessionList
        }
        .task { appCore.onboardingManager?.markCompleted("wh-receiving-view") }
        .navigationTitle("Receiving")
        .searchable(text: $searchText, prompt: "Search receiving sessions...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .startReceiving } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .startReceiving:
            NavigationStack {
                IOSReceiveShipmentPage()
                    .environmentObject(appCore)
            }
        case .continueSession:
            // IOSReceiveShipmentPage shows PO list; user picks the PO to continue
            NavigationStack {
                IOSReceiveShipmentPage()
                    .environmentObject(appCore)
            }
        case .help:
            PageHelpSheet(
                title: "Receiving Help",
                sections: [
                    ("Overview", "Track incoming shipments from suppliers. Each receiving session records what was ordered vs. what actually arrived."),
                    ("Starting a Session", "Tap + to start receiving against a purchase order. Scan or manually enter received quantities."),
                    ("Status Filters", "Use the smart cards to filter by active, completed, or cancelled sessions. Pull down to refresh.")
                ]
            )
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countForFilter(_ filter: StatusFilter) -> Int {
        sessions.filter { session in
            filter.matchStatuses.contains(session.status)
        }.count
    }

    private func smartCard(filter: StatusFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = filterColor(filter)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon(filter))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 90)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: StatusFilter) -> String {
        switch filter {
        case .active: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func filterColor(_ filter: StatusFilter) -> Color {
        switch filter {
        case .active: .blue
        case .completed: .green
        case .cancelled: .red
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        if isLoading {
            ProgressView("Loading receiving sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredSessions.isEmpty {
            if searchText.isEmpty && selectedFilter == nil {
                EmptyStateView(
                    icon: "shippingbox.and.arrow.backward",
                    title: "No Receiving Sessions",
                    message: "No active receiving sessions found. Tap + to start receiving a shipment."
                )
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No receiving sessions match your current filters."
                )
            }
        } else {
            List(filteredSessions, id: \.id) { session in
                let isActive = session.status == "in_progress" || session.status == "active"
                if isActive {
                    Button {
                        activeSheet = .continueSession(session.id)
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                } else {
                    sessionRow(session)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredSessions: [WarehouseService.ReceivingSessionInfo] {
        var result = sessions

        // Status filter
        if let filter = selectedFilter {
            result = result.filter { session in
                filter.matchStatuses.contains(session.status)
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.startedByName.lowercased().contains(query) ||
                $0.mode.lowercased().contains(query) ||
                String($0.poId).contains(query)
            }
        }

        return result
    }

    private func sessionRow(_ session: WarehouseService.ReceivingSessionInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(statusColor(session.status))
                .frame(width: 32, height: 32)
                .background(statusColor(session.status).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("PO #\(session.poId)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    modeBadge(session.mode)
                }
                Text("Started by \(session.startedByName)")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(formatDate(session.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(session.status)
                Label("\(session.itemCount) items", systemImage: "cube.box")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if session.status == "in_progress" || session.status == "active" {
                    Text("Tap to continue")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color = statusColor(status)
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_progress", "active": .blue
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
    }

    private func modeBadge(_ mode: String) -> some View {
        Text(mode.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .foregroundStyle(.purple)
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = sessions.isEmpty
        loadError = nil
        do {
            sessions = try service.getActiveSessions()
        } catch {
            loadError = userFriendlyError(error, context: "load receiving data")
        }
        isLoading = false
    }
}
