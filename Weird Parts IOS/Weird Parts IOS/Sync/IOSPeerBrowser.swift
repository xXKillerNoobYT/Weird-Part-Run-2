import SwiftUI
import WiredPartCore

/// Full-screen peer browser for discovering and connecting to nearby devices.
///
/// Used during "Join Existing Business" onboarding and from the Sync settings page.
/// Shows discovered peers with connection status and allows initiating pairing.
struct IOSPeerBrowser: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scanning indicator
                scanningHeader

                if syncManager.discoveredPeers.isEmpty {
                    emptyState
                } else {
                    peerList
                }
            }
            .navigationTitle("Nearby Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        syncManager.startPeerDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(syncManager.isScanning)
                    .accessibilityLabel("Scan again for nearby devices")
                }
            }
            .onAppear {
                syncManager.startPeerDiscovery()
            }
            .onDisappear {
                syncManager.stopPeerDiscovery()
            }
            .alert("Info", isPresented: Binding(
                get: { syncManager.errorMessage != nil },
                set: { if !$0 { syncManager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { syncManager.errorMessage = nil }
            } message: {
                if let msg = syncManager.errorMessage {
                    Text(msg)
                }
            }
        }
    }

    // MARK: - Scanning Header

    @ViewBuilder
    private var scanningHeader: some View {
        if syncManager.isScanning {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Scanning for nearby devices...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .decorativeIconFont(48)
                .foregroundStyle(.secondary)

            Text("No Devices Found")
                .font(.title3)
                .fontWeight(.semibold)

            // When the OS refused to start Bluetooth we know exactly why, so say
            // it here rather than offering generic advice (#1580). Logs travel
            // over the sync that is failing, so this is the only channel that
            // still works when Bluetooth is down.
            if let transportError = syncManager.bluetoothTransportError {
                VStack(spacing: 8) {
                    Label("Bluetooth could not start", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(transportError)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    Text("Bluetooth is required to find devices. Touch and hold the code above to copy it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bluetooth could not start")
                .accessibilityValue(transportError)
                .accessibilityIdentifier("peer-browser-transport-error")
            } else {
                Text("Bluetooth must be on and the devices near each other. Wi-Fi is optional — it only makes syncing faster.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !syncManager.isScanning {
                Button {
                    syncManager.startPeerDiscovery()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Peer List

    @ViewBuilder
    private var peerList: some View {
        List {
            Section("Discovered Devices (\(syncManager.discoveredPeers.count))") {
                ForEach(syncManager.discoveredPeers) { peer in
                    HStack(spacing: 12) {
                        Image(systemName: peerIcon(peer.state))
                            .foregroundStyle(peerColor(peer.state))
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(peer.state.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if peer.isBluetoothOnly {
                                Text("Send changes one way; use this on both devices to exchange data.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if peer.isManuallySyncable {
                            Button(peer.isBluetoothOnly ? "Send Changes" : "Sync") {
                                Task { await syncManager.syncWithPeer(peerDeviceId: peer.id) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(syncManager.syncStatus == .syncing)
                            .accessibilityLabel(peer.isBluetoothOnly ? "Send changes to \(peer.name)" : "Sync with \(peer.name)")
                            .accessibilityHint(peer.isBluetoothOnly
                                ? "Sends this device's pending changes. To receive \(peer.name)'s changes, tap Send Changes on that device."
                                : "Exchanges data with this device.")
                        } else if peer.state == "connecting" {
                            ProgressView()
                                .scaleEffect(0.7)
                                .accessibilityLabel("Status: Connecting")
                        } else if peer.state == "multipeer" {
                            Text("Waiting")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if peer.state == "connected" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Status: Connected")
                        } else {
                            // Neutral fallback for other unsyncable states
                            // (e.g. a LAN peer without a usable address).
                            Text("Unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 56)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func peerIcon(_ state: String) -> String {
        switch state {
        case "connected": return "desktopcomputer"
        case "connecting": return "arrow.triangle.2.circlepath"
        case "multipeer": return "antenna.radiowaves.left.and.right"
        case "lan": return "network"
        default: return "desktopcomputer.and.arrow.down"
        }
    }

    private func peerColor(_ state: String) -> Color {
        switch state {
        case "connected": return .green
        case "connecting": return .orange
        case "multipeer": return .blue
        case "lan": return Color.accentColor
        default: return Color.accentColor
        }
    }
}
