import SwiftUI

/// User-facing help actions that are not tied to a single feature page.
struct SettingsHelpPage: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("firstLaunchSheetSeen") private var firstLaunchSheetSeen = false
    @AppStorage("onboarding_checklist_dismissed") private var checklistDismissed = false
    @State private var showRestartConfirmation = false

    var body: some View {
        List {
            Section("Setup") {
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
            }
        }
        .navigationTitle("Help")
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
        checklistDismissed = false
        firstLaunchSheetSeen = false

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
