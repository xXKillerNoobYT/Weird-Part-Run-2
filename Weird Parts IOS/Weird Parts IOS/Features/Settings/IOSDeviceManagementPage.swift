import SwiftUI
import WiredPartCore

/// Device management page showing paired devices and their sync status.
struct IOSDeviceManagementPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        List {
            Section("This Device") {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIDevice.current.name)
                            .fontWeight(.medium)
                        Text("iOS \(UIDevice.current.systemVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 10, height: 10)
                        .accessibilityLabel("Status: Active")
                }
            }

            Section("Paired Devices") {
                ContentUnavailableView {
                    Label("No Paired Devices", systemImage: "desktopcomputer")
                } description: {
                    Text("Device pairing will be available when sync infrastructure is enabled in a future update.")
                }
            }

            Section("Actions") {
                Button {
                    // Pair new device
                } label: {
                    Label("Pair New Device", systemImage: "plus.circle.fill")
                }
                .disabled(true) // Enabled in Phase 16
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Device Management")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            Group {
                PageHelpSheet(title: "Device Management Help", sections: [
                    ("What This Page Does", "Shows this device's identity and lists all paired devices in your shop network. Paired devices can sync data with each other."),
                    ("How to Use It", "View your current device info at the top. Device pairing will be available when multi-device sync infrastructure is enabled in a future update."),
                ])
            }
            .presentationDetents([.medium, .large])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }
}
