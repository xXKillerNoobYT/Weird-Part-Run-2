import SwiftUI
import WiredPartCore

/// Shared Settings action for re-showing the first-launch setup checklist.
struct FirstLaunchSetupRestartRow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appCore: AppCore

    let telemetrySource: String

    @State private var showRestartConfirmation = false

    var body: some View {
        Button {
            showRestartConfirmation = true
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Restart setup checklist")
                        .foregroundStyle(.primary)
                    Text("Re-show the Getting set up card on the Dashboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checklist")
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityLabel("Restart setup checklist")
        .accessibilityHint("Re-shows the Getting set up card on the Dashboard.")
        .confirmationDialog(
            "Restart setup checklist?",
            isPresented: $showRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restart") {
                restartSetupChecklist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will re-show the Getting set up card on the Dashboard.")
        }
    }

    private func restartSetupChecklist() {
        FirstLaunchDefaults.restartChecklist()
        try? appCore.onboardingTelemetryService?.record(
            .checklistRestarted,
            payload: ["source": .string(telemetrySource)]
        )

        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": "dashboard", "tabId": "dashboard-home"]
        )
        NotificationCenter.default.post(name: .dismissSettingsSheet, object: nil)
        dismiss()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .onboardingScrollToChecklist, object: nil)
        }
    }
}
