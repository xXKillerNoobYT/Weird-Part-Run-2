import SwiftUI
import WiredPartCore

/// User-scoped account settings reached from the profile row in the user menu.
///
/// This first slice intentionally exposes only the existing self-service PIN
/// change capability. Administrator reset and recovery policy are tracked
/// separately and must not be inferred from this form.
struct IOSAccountPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var pinConfirmation = ""
    @State private var validationMessage: String?
    @State private var serviceMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        Form {
            if let user = appCore.currentUser {
                Section("Account") {
                    HStack(spacing: DS.Space.lg - 2) {
                        DSAvatarView(name: user.displayName, size: .medium)
                        VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                            Text(user.displayName)
                                .dsStyle(.sectionTitle)
                            if let email = user.email, !email.isEmpty {
                                Text(email)
                                    .dsStyle(.detail)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    SecureField("Current PIN", text: userEditedBinding($currentPIN))
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .accessibilityIdentifier("account-current-pin-field")

                    SecureField("New PIN", text: userEditedBinding($newPIN))
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("account-new-pin-field")

                    SecureField("Confirm New PIN", text: userEditedBinding($pinConfirmation))
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("account-confirm-new-pin-field")

                    if let validationMessage {
                        inlineMessage(
                            validationMessage,
                            color: .red,
                            accessibilityPrefix: "PIN validation error",
                            identifier: "account-pin-validation-error"
                        )
                    }

                    if let serviceMessage {
                        inlineMessage(
                            serviceMessage,
                            color: .red,
                            accessibilityPrefix: "PIN change error",
                            identifier: "account-pin-change-error"
                        )
                    }

                    if let successMessage {
                        inlineMessage(
                            successMessage,
                            color: .green,
                            accessibilityPrefix: "Success",
                            identifier: "account-pin-change-success"
                        )
                    }

                    Button {
                        Task { await submitPINChange(userId: user.id) }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSubmitting ? "Changing PIN…" : "Change PIN")
                                .frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("account-change-pin-button")
                } header: {
                    Text("Change PIN")
                } footer: {
                    Text("Use 4–8 digits. Your current PIN is required, and the new PIN must be entered twice.")
                }
            } else {
                Section {
                    Text("No signed-in user is available.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inlineMessage(
        _ message: String,
        color: Color,
        accessibilityPrefix: String,
        identifier: String
    ) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel("\(accessibilityPrefix): \(message)")
            .accessibilityIdentifier(identifier)
    }

    @MainActor
    private func submitPINChange(userId: Int64?) async {
        guard let userId else {
            serviceMessage = "No signed-in user is available."
            return
        }

        if let message = PINConfirmationValidator.changePINError(
            currentPIN: currentPIN,
            newPIN: newPIN,
            confirmation: pinConfirmation
        ) {
            validationMessage = message
            serviceMessage = nil
            successMessage = nil
            return
        }

        validationMessage = nil
        serviceMessage = nil
        successMessage = nil
        isSubmitting = true

        let result = await appCore.changePin(
            userId: userId,
            oldPin: PINConfirmationValidator.normalize(currentPIN),
            newPin: PINConfirmationValidator.normalize(newPIN)
        )
        isSubmitting = false

        if let result {
            serviceMessage = result
            return
        }

        currentPIN = ""
        newPIN = ""
        pinConfirmation = ""
        successMessage = "PIN changed successfully."
    }

    private func inputChanged() {
        serviceMessage = nil
        successMessage = nil
        guard validationMessage != nil else { return }
        validationMessage = PINConfirmationValidator.changePINError(
            currentPIN: currentPIN,
            newPIN: newPIN,
            confirmation: pinConfirmation
        )
    }

    /// Runs message cleanup for keyboard edits while allowing a successful
    /// submission to wipe sensitive fields without erasing its confirmation.
    private func userEditedBinding(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                inputChanged()
            }
        )
    }
}
