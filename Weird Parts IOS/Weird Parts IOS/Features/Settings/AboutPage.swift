import SwiftUI
import WiredPartCore

/// About page showing app version, core version, and system info.
struct AboutPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?

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
        .navigationTitle("About")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "About Help", sections: [
                ("What This Page Does", "Displays app version, core library version, database location, device information, and legal notices."),
                ("How to Use It", "Use this page to verify which version of the app and core library are running. Share device and version info when reporting issues."),
            ])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private var platformName: String {
        return "iOS"
    }
}
