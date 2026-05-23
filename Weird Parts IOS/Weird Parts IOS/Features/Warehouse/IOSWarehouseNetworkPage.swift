import SwiftUI
import WiredPartCore

/// Warehouse network status page showing device connectivity.
///
/// Displays current local device status and an intentional unavailable state
/// for multi-device discovery until sync infrastructure is implemented.
struct IOSWarehouseNetworkPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
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
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Network Discovery")
                        .font(.headline)
                    Text("Device network discovery is not enabled yet. For now, this page confirms the local database is active; multi-device status will appear here after sync infrastructure is configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Section("Network Sync Roadmap") {
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
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Network Help",
                sections: [
                    ("Overview", "View the network status of your device and connected shop computers, tablets, and phones."),
                    ("Sync", "After network sync is configured, this page will show real-time connectivity and sync status for all devices on your local network."),
                    ("Roadmap", "The next network milestones are LAN HTTP sync, Bluetooth P2P pairing, encrypted sync, and conflict resolution.")
                ]
            )
        }
        .onAppear { postAIContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseNetworkPageInactive, object: nil)
        }
    }

    private func postAIContext() {
        let context = """
        Warehouse Network page. Read-only context.
        This device status: Online, local database active. Connected device discovery is intentionally unavailable until sync infrastructure is configured.
        Planned features shown: LAN HTTP Sync, Multipeer Connectivity, Encrypted Sync, Conflict Resolution.
        Available read-only guidance: explain current local status and planned network sync capabilities. Do not attempt pairing, discovery, or sync actions directly.
        """
        NotificationCenter.default.post(
            name: .warehouseNetworkPageActive,
            object: nil,
            userInfo: ["context": context]
        )
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
