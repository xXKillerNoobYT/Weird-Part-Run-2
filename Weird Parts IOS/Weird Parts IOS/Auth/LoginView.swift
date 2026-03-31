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
    @State private var usersLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .decorativeIconFont(48)
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
                        .accessibilityIdentifier("loginBackButton")
                        Spacer()
                    }
                    .padding(.horizontal)

                    Text("Hello, \(selected.displayName)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    SecureField("Enter PIN", text: $pin)
                        .textContentType(.password)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .multilineTextAlignment(.center)
                        .onSubmit { attemptLogin() }
                        .accessibilityIdentifier("loginPINField")

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("loginErrorMessage")
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
                    .accessibilityIdentifier("loginSignInButton")
                }
                .padding()
            } else {
                // User list
                if users.isEmpty && !usersLoaded {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading users...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if users.isEmpty && usersLoaded {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Users Found")
                            .font(.headline)
                        Text("Create an admin account first using the onboarding flow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
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
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("loginUserRow_\(user.id ?? 0)")
                            }
                        }
                        .padding(.horizontal)
                        .accessibilityIdentifier("loginUserList")
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loginView")
        .background(Color(.systemBackground))
        .onAppear { loadUsers() }
    }

    // MARK: - Actions

    private func loadUsers() {
        guard let authService = appCore.authService else {
            errorMessage = "App not ready. Please wait."
            usersLoaded = true
            return
        }
        do {
            users = try authService.getActiveUsers()
        } catch {
            errorMessage = userFriendlyError(error, context: "load users")
        }
        usersLoaded = true
    }

    private func attemptLogin() {
        guard let user = selectedUser else {
            errorMessage = "No user selected."
            return
        }
        guard let userId = user.id else {
            errorMessage = "Invalid user account. Please contact your administrator."
            return
        }
        isLoading = true
        errorMessage = nil

        // Small delay for UX feedback
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            let result = await appCore.login(userId: userId, pin: pin)
            isLoading = false
            if let err = result {
                errorMessage = err
                pin = ""
            }
        }
    }
}
