import SwiftUI
import WiredPartCore

/// First-run setup screen for a brand-new device / company.
///
/// Collects the admin's display name and a PIN, then calls
/// `AuthService.seedFirstAdmin()` to create the initial database
/// records (hats, permissions, settings, admin user).
struct BootstrapView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var displayName = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pin.count >= 4
            && pin == confirmPin
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .decorativeIconFont(56)
                    .foregroundStyle(Color.accentColor)
                Text("Welcome to WiredPart")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Set up the first admin account for this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Form
            VStack(spacing: 16) {
                TextField("Your Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .frame(maxWidth: 300)

                SecureField("PIN (4+ digits)", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 300)

                SecureField("Confirm PIN", text: $confirmPin)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 300)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    performBootstrap()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Admin Account")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isLoading)
            }

            Spacer()

            Text("This creates the initial company database. All subsequent devices sync from this one.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func performBootstrap() {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            let result = await appCore.seedFirstAdmin(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                pin: pin
            )
            isLoading = false
            if let err = result {
                errorMessage = err
            }
        }
    }
}
