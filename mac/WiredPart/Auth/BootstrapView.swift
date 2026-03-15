import SwiftUI

/// First-run setup view. Creates the initial admin user and seeds the database.
///
/// Collects:
/// - Display name (required, non-empty)
/// - 4-digit PIN
/// - PIN confirmation
struct BootstrapView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var displayName: String = ""
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSubmitting: Bool = false

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && pin.count == 4
            && pin.allSatisfy(\.isNumber)
            && pin == confirmPin
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            content
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    private var content: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("Welcome to WiredPart")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Set up your first admin account to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("4-Digit PIN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Enter PIN", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: pin) { _, newValue in
                            // Enforce digits only, max 4
                            let filtered = String(newValue.filter(\.isNumber).prefix(4))
                            if filtered != newValue { pin = filtered }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirm PIN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Confirm PIN", text: $confirmPin)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: confirmPin) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(4))
                            if filtered != newValue { confirmPin = filtered }
                        }
                }
            }
            .frame(maxWidth: 320)

            // Validation hints
            VStack(spacing: 4) {
                validationRow("Name is not empty", passes: !displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                validationRow("PIN is exactly 4 digits", passes: pin.count == 4 && pin.allSatisfy(\.isNumber))
                validationRow("PINs match", passes: !pin.isEmpty && pin == confirmPin)
            }

            // Error
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Submit
            Button {
                submit()
            } label: {
                Text(isSubmitting ? "Setting up..." : "Create Admin Account")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || isSubmitting)
        }
        .padding(40)
    }

    private func validationRow(_ text: String, passes: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: passes ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(passes ? .green : .secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(passes ? .primary : .secondary)
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil

        do {
            try appCore.bootstrap(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                pin: pin
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
