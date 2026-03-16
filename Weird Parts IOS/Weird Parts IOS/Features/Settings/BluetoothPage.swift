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

    var body: some View {
        Form {
            Section("Bluetooth Sync") {
                Toggle("Enable Bluetooth Sync", isOn: $bluetoothEnabled)
                Toggle("Discoverable by Peers", isOn: $discoverable)
                    .disabled(!bluetoothEnabled)
            }

            Section("Nearby Devices") {
                Text("No nearby WiredPart devices found.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
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
    }
}
