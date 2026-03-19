import SwiftUI
import WiredPartCore

/// Full-screen peer browser for discovering and connecting to nearby devices.
///
/// Used during "Join Existing Business" onboarding and from the Sync settings page.
/// Shows discovered peers with connection status and allows initiating pairing.
struct IOSPeerBrowser: View {
    @State private var syncManager = IOSSyncManager()
    @Environment(\.dismiss) private var dismiss

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Devices Found")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Make sure other devices are on the same network or have Bluetooth enabled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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
                        }

                        Spacer()

                        if peer.state == "found" {
                            Button("Connect") {
                                syncManager.errorMessage = "Peer connection requires sync infrastructure (Phase 16)."
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if peer.state == "connecting" {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(minHeight: 56)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func peerIcon(_ state: String) -> String {
        switch state {
        case "connected": return "desktopcomputer"
        case "connecting": return "arrow.triangle.2.circlepath"
        default: return "desktopcomputer.and.arrow.down"
        }
    }

    private func peerColor(_ state: String) -> Color {
        switch state {
        case "connected": return .green
        case "connecting": return .orange
        default: return Color.accentColor
        }
    }
}
