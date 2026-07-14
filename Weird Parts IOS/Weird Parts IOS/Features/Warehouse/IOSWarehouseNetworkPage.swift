import SwiftUI
import WiredPartCore

/// Warehouse network status page showing device connectivity.
///
/// Displays current local device status, sync state, and connected-device
/// discovery actions backed by the shared iOS sync manager.
struct IOSWarehouseNetworkPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?

    private var syncManager: IOSSyncManager { appCore.syncManager }

    private enum ActiveSheet: Identifiable {
        case help
        case peerBrowser
        case addDevice

        var id: String {
            switch self {
            case .help: return "help"
            case .peerBrowser: return "peerBrowser"
            case .addDevice: return "addDevice"
            }
        }
    }

    var body: some View {
        List {
            // This device status
            Section("This Device") {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Online")
                            .fontWeight(.medium)
                        Text("Local database active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("Status: Online")
                }
            }

            Section("Connected Devices") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.title2)
                            .foregroundStyle(syncManager.isSyncAvailable ? Color.blue : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectedDevicesSummary)
                                .fontWeight(.medium)
                            Text(syncManager.isSyncAvailable ? discoveryDetailText : syncSetupDetailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            activeSheet = .peerBrowser
                        } label: {
                            Label("Browse Nearby Devices", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            syncManager.startPeerDiscovery()
                        } label: {
                            Label(syncManager.isScanning ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(syncManager.isScanning)
                    }
                    .labelStyle(.titleAndIcon)

                    // Post-onboarding pairing: let this device host a pairing code
                    // so a new phone/tablet can join the same company here (not
                    // only during first-run onboarding).
                    Button {
                        activeSheet = .addDevice
                    } label: {
                        Label("Add a Device", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .labelStyle(.titleAndIcon)

                    if let errorMessage = syncManager.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("warehouseNetwork_syncNotice")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Network Sync Capabilities") {
                featureRow(icon: "wifi", label: "LAN HTTP Sync", description: "Sync with shop computer over Wi-Fi")
                featureRow(icon: "dot.radiowaves.left.and.right", label: "Multipeer Connectivity", description: "Bluetooth and Wi-Fi P2P device pairing")
                featureRow(icon: "lock.shield", label: "Encrypted Sync", description: "TLS transport with field-level encryption")
                featureRow(icon: "arrow.triangle.2.circlepath", label: "Conflict Resolution", description: "Last-write-wins with field-level merge")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Network")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Network Help",
                    sections: [
                        ("Overview", "View this device's local database status, sync health, and nearby shop computers, tablets, and phones."),
                        ("Browse Devices", "Use Browse Nearby Devices or Scan to open the live discovery flow backed by LAN and Bluetooth sync settings."),
                        ("Capabilities", "Supported network milestones are LAN HTTP sync, Bluetooth P2P pairing, encrypted sync, and conflict resolution.")
                    ]
                )
            case .peerBrowser:
                IOSPeerBrowser()
                    .environmentObject(appCore)
            case .addDevice:
                IOSAddDeviceSheet()
                    .environmentObject(appCore)
            }
        }
        .onAppear { postAIContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseNetworkPageInactive, object: nil)
        }
    }

    private func postAIContext() {
        let context = """
        Warehouse Network page. Read-only context.
        This device status: Online, local database active. Sync status: \(syncStatusLabel); pending changes: \(syncManager.pendingChanges); discovered devices: \(syncManager.discoveredPeers.count).
        Available actions: Browse Nearby Devices opens the live peer browser; Scan starts peer discovery through IOSSyncManager; Help explains network capabilities.
        Network sync capabilities shown: LAN HTTP Sync, Multipeer Connectivity, Encrypted Sync, Conflict Resolution.
        """
        NotificationCenter.default.post(
            name: .warehouseNetworkPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    private var connectedDevicesSummary: String {
        if syncManager.isScanning {
            return "Scanning for nearby devices"
        }
        let count = syncManager.discoveredPeers.count
        if count == 0 {
            return "No nearby devices discovered"
        }
        return count == 1 ? "1 nearby device discovered" : "\(count) nearby devices discovered"
    }

    private var discoveryDetailText: String {
        if syncManager.discoveredPeers.isEmpty {
            return "Browse or scan for configured LAN/Bluetooth peers on the shop network."
        }
        return "Open the browser to review discovered peers and start a sync."
    }

    private var syncSetupDetailText: String {
        "Configure Bluetooth sync or a shop server address in Settings, then scan from here."
    }

    private var syncStatusLabel: String {
        switch syncManager.syncStatus {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .error: return "Error"
        case .offline: return "Offline"
        }
    }

    private func featureRow(icon: String, label: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
