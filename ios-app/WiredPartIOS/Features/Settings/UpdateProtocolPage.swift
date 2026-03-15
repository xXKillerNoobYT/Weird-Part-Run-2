import SwiftUI
import WiredPartCore

/// Update protocol settings page.
///
/// Describes how app updates are distributed across the fleet.
/// The WiredPart app uses a shop-server-based update protocol
/// where the shop computer hosts the latest version and devices
/// pull updates over LAN.
struct UpdateProtocolPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        Form {
            Section("Current Version") {
                LabeledContent("App Version", value: "1.0.0")
                LabeledContent("Core Version", value: WiredPartCore.version)
                LabeledContent("Build", value: "Release")
            }

            Section("Update Channel") {
                LabeledContent("Channel", value: "Stable")
                LabeledContent("Distribution", value: "Shop Server / App Store")
            }

            Section("How Updates Work") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Shop computer downloads the latest release", systemImage: "1.circle.fill")
                    Label("Connected devices are notified of the update", systemImage: "2.circle.fill")
                    Label("Each device downloads and installs the update", systemImage: "3.circle.fill")
                    Label("Database migrations run automatically on launch", systemImage: "4.circle.fill")
                }
                .font(.subheadline)
            }

            Section {
                Text("iOS devices receive updates through the App Store or TestFlight. The shop server update protocol applies to desktop and web clients.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
