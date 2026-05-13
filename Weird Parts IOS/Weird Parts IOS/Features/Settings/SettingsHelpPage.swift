import SwiftUI
import WiredPartCore

/// User-facing help actions that are not tied to a single feature page.
struct SettingsHelpPage: View {
    var body: some View {
        List {
            Section("Setup") {
                FirstLaunchSetupRestartRow(telemetrySource: "settingsHelp")
            }
        }
        .navigationTitle("Help")
    }
}
