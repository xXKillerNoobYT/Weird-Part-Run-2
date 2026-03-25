import SwiftUI
import WiredPartCore

/// Bluetooth / Multipeer Connectivity settings page.
///
/// Shows the status of nearby peer discovery and allows enabling
/// or disabling Bluetooth mesh sync. The actual Multipeer
/// connectivity is managed by the core package's PeerDiscovery
/// and MultipeerManager.
struct BluetoothPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var bluetoothEnabled = false
    @State private var discoverable = false

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        Form {
            Section("Bluetooth Sync") {
                Toggle("Enable Bluetooth Sync", isOn: $bluetoothEnabled)
                    .onChange(of: bluetoothEnabled) { _, newValue in
                        syncManager.setBluetoothEnabled(newValue)
                        if !newValue { discoverable = false }
                    }
                Toggle("Discoverable by Peers", isOn: $discoverable)
                    .disabled(!bluetoothEnabled)
                    .onChange(of: discoverable) { _, newValue in
                        if newValue {
                            syncManager.startPeerDiscovery()
                        } else {
                            syncManager.stopPeerDiscovery()
                        }
                    }
            }

            Section("Nearby Devices") {
                if syncManager.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning for nearby devices...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if syncManager.discoveredPeers.isEmpty {
                    if !syncManager.isScanning {
                        Text("No nearby WiredPart devices found.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(syncManager.discoveredPeers) { peer in
                        HStack(spacing: 12) {
                            Image(systemName: peerIcon(peer.state))
                                .foregroundStyle(peerColor(peer.state))
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(peerTransportLabel(peer.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if peer.state == "connected" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Sync") {
                                    Task { await syncManager.syncNow() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .frame(minHeight: 48)
                    }
                }
            }

            Section("How It Works") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Uses Apple Multipeer Connectivity", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Works over Bluetooth and Wi-Fi Direct", systemImage: "wifi")
                    Label("Syncs changes between nearby devices", systemImage: "arrow.triangle.2.circlepath")
                    Label("Encrypted with Ed25519 signatures", systemImage: "lock.shield.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text("Bluetooth sync enables peer-to-peer data exchange when devices are nearby, even without a shop server connection. All data is signed and verified before merging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            bluetoothEnabled = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
        }
    }

    // MARK: - Peer Helpers

    private func peerIcon(_ state: String) -> String {
        switch state {
        case "connected": return "desktopcomputer"
        case "multipeer": return "antenna.radiowaves.left.and.right"
        case "lan": return "network"
        default: return "desktopcomputer.and.arrow.down"
        }
    }

    private func peerColor(_ state: String) -> Color {
        switch state {
        case "connected": return .green
        case "multipeer": return .blue
        case "lan": return Color.accentColor
        default: return .secondary
        }
    }

    private func peerTransportLabel(_ state: String) -> String {
        switch state {
        case "connected": return "Connected"
        case "multipeer": return "Bluetooth / Wi-Fi Direct"
        case "lan": return "Local Network"
        default: return state.capitalized
        }
    }
}
