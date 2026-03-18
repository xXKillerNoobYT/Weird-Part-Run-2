import SwiftUI
import WiredPartCore

/// Admin account creation — second step of the "Create New Business" path.
///
/// Collects admin display name and PIN, then calls `seedFirstAdmin()`
/// to create the initial database records (hats, permissions, settings, admin user).
/// On success, navigates to OnboardingCompleteView.
struct AdminAccountSetupView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var displayName = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var navigateToComplete = false

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && pin.count >= 4
            && pin == confirmPin
    }

    private var pinMismatch: Bool {
        !confirmPin.isEmpty && pin != confirmPin
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Admin Account")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Create the first admin account. This user will have full access to all features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 16)

                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Name")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity)

                // PIN
                VStack(alignment: .leading, spacing: 8) {
                    Text("PIN Code")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

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

                    if pinMismatch {
                        Text("PINs do not match")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Create Button
                Button {
                    performSetup()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Admin Account")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 300)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isLoading)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Admin Setup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(isPresented: $navigateToComplete) {
            OnboardingCompleteView()
                .environmentObject(appCore)
        }
    }

    // MARK: - Actions

    private func performSetup() {
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
            } else {
                navigateToComplete = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        AdminAccountSetupView()
            .environmentObject(AppCore())
    }
}
