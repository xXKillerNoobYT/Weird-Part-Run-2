import SwiftUI
import WiredPartCore

/// Device management page showing paired devices and their sync status.
struct IOSDeviceManagementPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        List {
            Section("This Device") {
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIDevice.current.name)
                            .fontWeight(.medium)
                        Text("iOS \(UIDevice.current.systemVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(.green).frame(width: 10, height: 10)
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Device Management")
    }
}
