import SwiftUI
import WiredPartCore

/// Warehouse network status page showing device connectivity.
///
/// Displays mesh relay / device network status for devices connected
/// to the warehouse. Shows paired devices, connection status, and
/// last sync times. Full implementation in Phase 16 (Sync Infrastructure).
struct IOSWarehouseNetworkPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var isScanning = false

    /// Placeholder device info for the network display
    private struct NetworkDevice: Identifiable {
        let id = UUID()
        let name: String
        let type: String
        let status: ConnectionStatus
        let lastSeen: String

        enum ConnectionStatus: String {
            case connected = "Connected"
            case disconnected = "Disconnected"
            case syncing = "Syncing"

            var color: Color {
                switch self {
                case .connected: return .green
                case .disconnected: return .secondary
                case .syncing: return .orange
                }
            }

            var icon: String {
                switch self {
                case .connected: return "wifi"
                case .disconnected: return "wifi.slash"
                case .syncing: return "arrow.triangle.2.circlepath"
                }
            }
        }
    }

    var body: some View {
        List {
            // Network status
            Section("Network Status") {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Device")
                            .fontWeight(.medium)
                        Text("Online — Local network active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                }
            }

            // Connected devices
            Section {
                ContentUnavailableView {
                    Label("No Other Devices", systemImage: "desktopcomputer")
                } description: {
                    Text("Pair devices to see them here. LAN sync and Multipeer Connectivity will be available in a future update.")
                }
            } header: {
                HStack {
                    Text("Devices")
                    Spacer()
                    Button {
                        scanForDevices()
                    } label: {
                        HStack(spacing: 4) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(isScanning ? "Scanning..." : "Scan")
                                .font(.caption)
                        }
                    }
                    .disabled(isScanning)
                }
            }

            // Network info
            Section("Network Info") {
                infoRow(label: "Protocol", value: "LAN HTTP + Multipeer")
                infoRow(label: "Sync Mode", value: "LWW (Last Write Wins)")
                infoRow(label: "Encryption", value: "TLS / PGP")
                infoRow(label: "Status", value: "Pending Phase 16")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Network")
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func scanForDevices() {
        isScanning = true
        // Placeholder — actual Multipeer/LAN discovery in Phase 16
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isScanning = false
        }
    }
}
