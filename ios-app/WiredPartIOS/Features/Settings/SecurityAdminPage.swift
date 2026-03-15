import SwiftUI
import WiredPartCore

/// Security administration settings page.
///
/// Configures security-related settings like auto-lock, session
/// timeout, and PIN requirements. Reads/writes settings via
/// SettingsService.
struct SecurityAdminPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var autoLockMinutes = "15"
    @State private var requirePinLength = "4"
    @State private var maxLoginAttempts = "5"
    @State private var saved = false

    var body: some View {
        Form {
            Section("Session Security") {
                HStack {
                    Text("Auto-Lock Timeout (minutes)")
                    Spacer()
                    TextField("15", text: $autoLockMinutes)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }

            Section("PIN Policy") {
                HStack {
                    Text("Minimum PIN Length")
                    Spacer()
                    TextField("4", text: $requirePinLength)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                HStack {
                    Text("Max Login Attempts")
                    Spacer()
                    TextField("5", text: $maxLoginAttempts)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }

            Section("Authentication") {
                LabeledContent("Method", value: "PIN (SHA-256)")
                LabeledContent("Token Expiry", value: "24 hours")
                LabeledContent("Token Type", value: "Local base64 JSON")
            }

            Section {
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Security Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        do {
            let map = try appCore.settingsService.getSettingsByCategory("security")
            autoLockMinutes = map["auto_lock_minutes"] ?? "15"
            requirePinLength = map["require_pin_length"] ?? "4"
            maxLoginAttempts = map["max_login_attempts"] ?? "5"
        } catch {}
    }

    private func saveSettings() {
        do {
            try appCore.settingsService.upsertSettingsMap([
                "auto_lock_minutes": autoLockMinutes,
                "require_pin_length": requirePinLength,
                "max_login_attempts": maxLoginAttempts,
            ], category: "security")
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {}
    }
}
