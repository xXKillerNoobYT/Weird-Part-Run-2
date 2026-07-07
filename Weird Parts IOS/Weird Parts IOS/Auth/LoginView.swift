import SwiftUI
import WiredPartCore

/// User selection and PIN entry screen.
///
/// Shows a list of active users fetched from the local database.
/// The user taps their name, enters a 4+ digit PIN, and authenticates
/// against the local SHA-256 hash.
struct LoginView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var pin = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var usersLoaded = false
    @State private var showStartOverConfirmation = false
    @FocusState private var pinFocused: Bool

    private var isAccessibilitySize: Bool {
        dynamicTypeSize >= .accessibility1
    }

    private var shouldCollapseSelectedUserHeader: Bool {
        selectedUser != nil && isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            if !shouldCollapseSelectedUserHeader {
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
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
                .padding(.horizontal)
            }

            if let selected = selectedUser {
                // PIN entry for selected user
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Button {
                                withAnimation {
                                    selectedUser = nil
                                    pin = ""
                                    errorMessage = nil
                                    pinFocused = false
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("loginBackButton")
                            Spacer()
                        }
                        .padding(.horizontal)

                        Text("Hello, \(selected.displayName)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        SecureField("Enter PIN", text: $pin)
                            .textContentType(.password)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            .multilineTextAlignment(.center)
                            .focused($pinFocused)
                            .onSubmit { attemptLogin() }
                            .accessibilityIdentifier("loginPINField")
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button {
                                        pinFocused = false
                                    } label: {
                                        Text("Done")
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .accessibilityIdentifier("loginPINDoneButton")
                                }
                            }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    // Reachable mid-Bluetooth-join (data landed before users) or
                    // after a failed initial sync. Must never be a dead end —
                    // offer a re-check (sync may have just delivered the users)
                    // and a way back to onboarding (2026-07-06 audit, #1417).
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Users Found")
                            .font(.headline)
                        Text("If this device just joined a company, the user list may still be syncing — check again in a moment. Or start over to create or join a company.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            usersLoaded = false
                            loadUsers()
                        } label: {
                            Label("Check Again", systemImage: "arrow.clockwise")
                                .frame(minWidth: 170, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("login-no-users-check-again")

                        Button {
                            showStartOverConfirmation = true
                        } label: {
                            Text("Start Over")
                                .frame(minWidth: 170, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("login-no-users-start-over")
                        .confirmationDialog(
                            "Go back to setup?",
                            isPresented: $showStartOverConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Back to Setup") {
                                // Mirrors AppCore's bootstrap reset: clearing the
                                // flags + needsOnboarding routes back to Welcome
                                // (Create New Business / Join Existing Business).
                                UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                                UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
                                appCore.needsOnboarding = true
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You'll return to the setup screen where you can create a company or join an existing one. Data already synced to this device is kept.")
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
                                        pinFocused = true
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loginView")
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if selectedUser != nil {
                VStack(spacing: 12) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("loginErrorMessage")
                    }

                    Button {
                        attemptLogin()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pin.count < 4 || isLoading)
                    .accessibilityIdentifier("loginSignInButton")
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .onAppear { loadUsers() }
        .onChange(of: selectedUser?.id) { _, newValue in
            pinFocused = newValue != nil
        }
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
