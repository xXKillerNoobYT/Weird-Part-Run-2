import SwiftUI
import WiredPartCore

/// Receiving incoming shipments page for iOS.
///
/// Shows active and recent receiving sessions for purchase orders.
/// Displays PO ID, started-by name, mode, status, and item count.
/// Supports pull-to-refresh and status-based filtering.
struct IOSReceivingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var sessions: [WarehouseService.ReceivingSessionInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        sessionList
            .navigationTitle("Receiving")
            .searchable(text: $searchText, prompt: "Search receiving sessions...")
            .onChange(of: searchText) { /* local filter only */ }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        if isLoading {
            ProgressView("Loading receiving sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSessions.isEmpty {
            ContentUnavailableView {
                Label("No Receiving Sessions", systemImage: "shippingbox.and.arrow.backward")
            } description: {
                Text("No active receiving sessions found.")
            }
        } else {
            List(filteredSessions, id: \.id) { session in
                sessionRow(session)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredSessions: [WarehouseService.ReceivingSessionInfo] {
        guard !searchText.isEmpty else { return sessions }
        let query = searchText.lowercased()
        return sessions.filter {
            $0.startedByName.lowercased().contains(query) ||
            $0.mode.lowercased().contains(query) ||
            String($0.poId).contains(query)
        }
    }

    private func sessionRow(_ session: WarehouseService.ReceivingSessionInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(statusColor(session.status))
                .frame(width: 32)

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
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color = statusColor(status)
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_progress", "active": return .blue
        case "completed": return .green
        case "cancelled": return .red
        default: return .secondary
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
        guard let service = appCore.warehouseService else { return }
        isLoading = sessions.isEmpty
        do {
            sessions = try service.getActiveSessions()
        } catch {
            print("[IOSReceivingPage] Load error: \(error)")
        }
        isLoading = false
    }
}
