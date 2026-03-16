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
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && pin.count >= 4
            && pin == confirmPin
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 56))
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
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(maxWidth: 300)

                SecureField("Confirm PIN", text: $confirmPin)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
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
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(Color(.systemGroupedBackground))
        #endif
    }

    // MARK: - Actions

    private func performBootstrap() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let result = appCore.seedFirstAdmin(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                pin: pin
            )
            isLoading = false
            if let err = result {
                errorMessage = err
            }
        }
    }
}
