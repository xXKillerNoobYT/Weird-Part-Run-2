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
                LabeledContent("Location", value: AppCore.databasePath())
                    .font(.caption2)
            }

            Section("Device") {
                #if os(iOS)
                LabeledContent("Device", value: UIDevice.current.name)
                LabeledContent("OS", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                #else
                LabeledContent("OS", value: "macOS")
                #endif
            }

            Section("Legal") {
                Text("WiredPart is proprietary software. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var platformName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }
}
