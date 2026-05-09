import SwiftUI
import WiredPartCore

/// User selection and PIN entry screen.
///
/// Shows a list of active users fetched from the local database.
/// The user taps their name, enters a 4+ digit PIN, and authenticates
/// against the local SHA-256 hash.
///
/// Face ID / Touch ID flow (WEI-301):
///   - On first successful PIN login, if biometry is available, the user is asked
///     whether they want to enable Face ID for future logins.
///   - On subsequent launches, if an opted-in user is known, biometric auth is
///     attempted automatically; failure or cancellation falls back to the PIN flow
///     with the user pre-selected.
struct LoginView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var pin = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var usersLoaded = false

    // MARK: - Biometric state (WEI-301)

    private let biometricService = BiometricAuthService()

    /// Controls the Face ID opt-in sheet shown after a successful PIN login.
    @State private var isBiometricOptInSheetPresented = false
    /// The userId that just completed a successful PIN login (used to record opt-in).
    @State private var pendingOptInUserId: Int64?
    /// Shown while the biometric prompt or biometric-based login is running.
    @State private var isBiometricRunning = false
    /// Controls the Forgot PIN help sheet.
    @State private var showForgotPIN = false
    /// Controls the Bootstrap setup sheet (shown when needsBootstrap is detected while on login screen).
    @State private var showBootstrap = false

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

            if isBiometricRunning {
                // Shown briefly while the biometric prompt is being evaluated on launch.
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking Face ID…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let selected = selectedUser {
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

                    // Forgot PIN recovery
                    Button {
                        showForgotPIN = true
                    } label: {
                        Text("Forgot PIN?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("loginForgotPINButton")
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
                    // Empty-users state — worker-readable copy (WEI-302)
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No accounts on this device yet.")
                            .font(.headline)
                        Text("Ask your supervisor to add you, or run setup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        // Tertiary "Run setup" button — only when a setup token is present (WEI-302).
                        // The setup token is written to UserDefaults by the pairing / bootstrap flow.
                        if UserDefaults.standard.string(forKey: "setup_token") != nil {
                            Button("Run Setup") {
                                showBootstrap = true
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                            .font(.footnote)
                            .padding(.top, 4)
                            .accessibilityIdentifier("loginRunSetupButton")
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
        .onAppear {
            loadUsers()
            tryBiometricOnLaunch()
        }
        // MARK: Forgot PIN help sheet
        .sheet(isPresented: $showForgotPIN) {
            ForgotPINHelpView()
                .environmentObject(appCore)
        }
        // MARK: Bootstrap setup sheet (edge case: profile exists, no accounts)
        .sheet(isPresented: $showBootstrap) {
            BootstrapView()
                .environmentObject(appCore)
        }
        // MARK: Face ID opt-in sheet (WEI-301)
        .sheet(isPresented: $isBiometricOptInSheetPresented) {
            BiometricOptInSheet(
                biometryKind: biometricService.availableBiometry,
                onEnable: {
                    if let uid = pendingOptInUserId {
                        biometricService.setOptIn(userId: uid, enabled: true)
                    }
                    isBiometricOptInSheetPresented = false
                },
                onSkip: {
                    isBiometricOptInSheetPresented = false
                }
            )
            .presentationDetents([.medium])
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
            } else {
                // PIN auth succeeded — offer Face ID opt-in if available and not already set.
                pin = ""
                if biometricService.isBiometryAvailable && !biometricService.isOptedIn(userId: userId) {
                    pendingOptInUserId = userId
                    isBiometricOptInSheetPresented = true
                }
            }
        }
    }

    // MARK: - Biometric Launch Flow (WEI-301)

    /// Called on `.onAppear` — tries biometric auth if a user has opted in.
    /// On success, logs the user in without PIN. On failure or cancel, pre-selects
    /// the opted-in user in the PIN flow so they don't have to scroll the list.
    private func tryBiometricOnLaunch() {
        guard biometricService.preferredBiometricUserId != nil else { return }
        isBiometricRunning = true
        Task { @MainActor in
            let biometricResult = await biometricService.attemptBiometricAuth()
            isBiometricRunning = false
            switch biometricResult {
            case .success(let userId):
                let loginError = await appCore.loginByBiometric(userId: userId)
                if let err = loginError {
                    // Biometric accepted by OS but user became inactive — rare, fall through to PIN.
                    errorMessage = err
                    preSelectUserById(userId)
                }
            case .fallback(let userId):
                if let userId {
                    preSelectUserById(userId)
                }
            case .notAvailable:
                break
            }
        }
    }

    /// Pre-selects a user in the list by their ID (used for biometric fallback).
    private func preSelectUserById(_ userId: Int64) {
        guard let match = users.first(where: { $0.id == userId }) else { return }
        withAnimation {
            selectedUser = match
            errorMessage = nil
        }
    }
}

// MARK: - BiometricOptInSheet

/// Sheet presented after the first successful PIN login offering to enable Face ID.
private struct BiometricOptInSheet: View {
    let biometryKind: BiometricAuthService.BiometryKind
    let onEnable: () -> Void
    let onSkip: () -> Void

    private var biometryName: String {
        switch biometryKind {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .none:    return "Biometrics"
        }
    }

    private var biometryIcon: String {
        switch biometryKind {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .none:    return "lock.shield"
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: biometryIcon)
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 32)

            VStack(spacing: 8) {
                Text("Enable \(biometryName)?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Sign in faster next time with \(biometryName) instead of your PIN. You can always change this in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    onEnable()
                } label: {
                    Label("Enable \(biometryName)", systemImage: biometryIcon)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("biometricOptInEnableButton")

                Button("Not Now") {
                    onSkip()
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("biometricOptInSkipButton")
            }

            Spacer()
        }
        .accessibilityIdentifier("biometricOptInSheet")
    }
}
