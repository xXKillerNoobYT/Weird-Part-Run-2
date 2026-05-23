import SwiftUI
import WiredPartCore

/// Warehouse network status page showing device connectivity.
///
/// Displays local device network status plus read-only guidance for
/// network sync features that depend on the sync infrastructure.
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
                    Text("Network Sync Not Active")
                        .font(.headline)
                    Text("This beta uses the local database on this device. Connected shop computers, tablets, and phones will appear here after network sync is configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Section("Sync Capabilities") {
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
                    ("Overview", "View this device's local database status and the network sync capabilities expected by the shop workflow."),
                    ("Current Beta", "Network discovery and pairing are not active on this screen yet, so there are no buttons to pair devices or start sync from here."),
                    ("Sync Capabilities", "The design targets LAN HTTP sync, Bluetooth P2P pairing, encrypted sync, and conflict resolution after the sync infrastructure is configured.")
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
        This device status: Online, local database active. Connected device discovery is not active in this beta.
        Sync capabilities shown: LAN HTTP Sync, Multipeer Connectivity, Encrypted Sync, Conflict Resolution.
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
