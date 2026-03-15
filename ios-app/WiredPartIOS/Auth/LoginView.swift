import SwiftUI
import WiredPartCore

/// User selection and PIN entry screen.
///
/// Shows a list of active users fetched from the local database.
/// The user taps their name, enters a 4+ digit PIN, and authenticates
/// against the local SHA-256 hash.
struct LoginView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var pin = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("WiredPart")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Select your name and enter your PIN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            if let selected = selectedUser {
                // PIN entry for selected user
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            withAnimation {
                                selectedUser = nil
                                pin = ""
                                errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    Text("Hello, \(selected.displayName)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    SecureField("Enter PIN", text: $pin)
                        .textContentType(.password)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .multilineTextAlignment(.center)
                        .onSubmit { attemptLogin() }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        attemptLogin()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count < 4 || isLoading)
                }
                .padding()
            } else {
                // User list
                if users.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading users...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(users, id: \.id) { user in
                                Button {
                                    withAnimation {
                                        selectedUser = user
                                        errorMessage = nil
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(Color.accentColor)
                                        Text(user.displayName)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            #if os(iOS)
                                            .fill(Color(.secondarySystemBackground))
                                            #elseif os(macOS)
                                            .fill(Color(.controlBackgroundColor))
                                            #endif
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .onAppear { loadUsers() }
    }

    // MARK: - Actions

    private func loadUsers() {
        do {
            users = try appCore.authService.getActiveUsers()
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
        }
    }

    private func attemptLogin() {
        guard let user = selectedUser, let userId = user.id else { return }
        isLoading = true
        errorMessage = nil

        // Small delay for UX feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let result = appCore.login(userId: userId, pin: pin)
            isLoading = false
            if let err = result {
                errorMessage = err
                pin = ""
            }
        }
    }
}
