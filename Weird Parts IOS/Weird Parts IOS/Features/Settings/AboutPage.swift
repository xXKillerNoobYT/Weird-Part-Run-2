import SwiftUI
import WiredPartCore

/// About page showing app version, core version, and system info.
struct AboutPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("App Name", value: "WiredPart iOS")
                LabeledContent("Core Version", value: WiredPartCore.version)
                LabeledContent("Platform", value: platformName)
            }

            Section("Database") {
                LabeledContent("Location", value: (try? AppCore.databasePath()) ?? "Unknown")
                    .font(.caption2)
            }

            Section("Device") {
                LabeledContent("Device", value: UIDevice.current.name)
                LabeledContent("OS", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            }

            Section("Legal") {
                Text("WiredPart is proprietary software. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var platformName: String {
        return "iOS"
    }
}
