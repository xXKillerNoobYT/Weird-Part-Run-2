import SwiftUI
import WiredPartCore

/// Compact sync status indicator shown in the main navigation bar.
///
/// Shows a colored dot and label reflecting current sync state.
/// Tap to expand into a detail popover with last sync time,
/// pending changes count, and a manual sync button.
struct IOSSyncStatusView: View {
    @EnvironmentObject private var appCore: AppCore

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        Menu {
            Section("Sync Status") {
                Label(statusLabel, systemImage: statusIcon)
            }

            if let lastSync = syncManager.lastSyncDate {
                Section("Last Sync") {
                    Text(lastSync.prefix(19).replacingOccurrences(of: "T", with: " "))
                }
            }

            if syncManager.pendingChanges > 0 {
                Section {
                    Label("\(syncManager.pendingChanges) pending changes", systemImage: "arrow.up.circle")
                }
            }

            Section {
                Button {
                    Task { await syncManager.syncNow() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncManager.syncStatus == .syncing)
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                if syncManager.syncStatus == .syncing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }
    }

    private var statusLabel: String {
        if let summary = syncManager.lastOneWayBluetoothSyncSummary {
            return summary
        }
        switch syncManager.syncStatus {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error: return "Error"
        case .offline: return "Offline"
        }
    }

    private var statusIcon: String {
        if syncManager.lastOneWayBluetoothSyncSummary != nil {
            return "arrow.up.circle.fill"
        }
        switch syncManager.syncStatus {
        case .idle: return "circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    private var statusColor: Color {
        if syncManager.lastOneWayBluetoothSyncSummary != nil {
            return .orange
        }
        switch syncManager.syncStatus {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        case .offline: return .orange
        }
    }
}
