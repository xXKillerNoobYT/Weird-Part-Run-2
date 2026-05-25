import SwiftUI
import WiredPartCore

/// Main entry point for the WiredPart iOS application.
///
/// Initializes the shared AppCore (database + services) before
/// presenting any UI. On first launch the database is created
/// in the app's Documents directory; subsequent launches reopen it.
@main
struct WiredPartIOSApp: App {
    @StateObject private var appCore = AppCore()
    @StateObject private var tabPrefs = TabBarPreferences()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasCompletedCompanySetup") private var hasCompletedCompanySetup = false
    @AppStorage("hasSeenOnboardAIMVPEntry") private var hasSeenOnboardAIMVPEntry = false
    @AppStorage(OnboardAIFeatureFlag.onboardingMVP) private var onboardAIMVPEnabled = false

    /// Pending crash-report info collected from the previous session.
    @State private var pendingCrashInfo: String?
    @State private var showCrashReportAlert = false

    init() {
        // Install crash reporter FIRST so it can read any previous crash state
        // before marking this session as active.
        CrashReporter.shared.install()

        // One-time migration: users who already completed the old welcome flow
        // don't need to re-run the walkthrough or company-setup wizard.
        // Consume hasSeenWelcome immediately so this never re-fires on a
        // subsequent fresh build where the DB is empty but UserDefaults persisted.
        if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
            if !UserDefaults.standard.bool(forKey: "hasCompletedCompanySetup") {
                UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")
            }
            // Clear the trigger so a future fresh-DB build doesn't re-apply
            // these flags before bootstrap() can detect the empty database.
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }
    }

    /// True if the current user has admin-level permissions.
    private var isAdmin: Bool {
        appCore.hasPermission("manage_people") && appCore.hasPermission("manage_jobs")
    }

    private var shouldOpenWarehouseSetupForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWarehouseSetupWizard")
    }

    private var shouldForceLoginForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingForceLogin")
    }

    private var shouldShowWEI936WelcomeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI936Welcome")
    }

    private var shouldShowWEI936CelebrationFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI936Celebration")
    }

    /// Resolved color scheme from the user's theme setting.
    private var resolvedColorScheme: ColorScheme? {
        switch appCore.theme.themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// Accent color parsed from the user's theme hex string.
    private var accentColor: Color {
        Color(hex: appCore.theme.primaryColor) ?? .accentColor
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appCore.isReady {
                    if shouldShowWEI936WelcomeFixture {
                        OnboardingWelcomeView()
                            .environmentObject(appCore)
                    } else if shouldShowWEI936CelebrationFixture {
                        NavigationStack {
                            OnboardingCompleteView()
                                .environmentObject(appCore)
                        }
                    } else if appCore.needsOnboarding {
                        OnboardingWelcomeView()
                            .environmentObject(appCore)
                    } else if appCore.needsBootstrap {
                        BootstrapView()
                            .environmentObject(appCore)
                    } else if shouldForceLoginForUITest || appCore.currentUser == nil {
                        LoginView()
                            .environmentObject(appCore)
                    } else if isAdmin && !hasCompletedCompanySetup {
                        CompanySetupWizard()
                            .environmentObject(appCore)
                    } else if onboardAIMVPEnabled && !hasSeenOnboardAIMVPEntry {
                        OnboardAIMVPEntryView()
                            .environmentObject(appCore)
                    } else if !hasCompletedOnboarding {
                        OnboardingWalkthroughView()
                            .environmentObject(appCore)
                    } else if shouldOpenWarehouseSetupForUITest {
                        WarehouseOnboardingWizard()
                            .environmentObject(appCore)
                    } else {
                        IOSMainView()
                            .environmentObject(appCore)
                            .environmentObject(tabPrefs)
                            .environmentObject(appCore.badgeCountManager)
                    }
                } else if let error = appCore.loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Failed to load database")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            appCore.retryBootstrap()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    LoadingView()
                }
            }
            .preferredColorScheme(resolvedColorScheme)
            .tint(accentColor)
            // Show crash-report prompt once the app is ready and a previous crash was detected.
            .onAppear {
                if CrashReporter.shared.hasPendingCrashReport {
                    pendingCrashInfo = CrashReporter.shared.pendingCrashInfo
                    showCrashReportAlert = true
                }
            }
            .alert("The app crashed last time", isPresented: $showCrashReportAlert) {
                Button("Report on GitHub") {
                    submitCrashReport()
                }
                Button("Dismiss", role: .cancel) {
                    CrashReporter.shared.clearPendingCrashReport()
                    pendingCrashInfo = nil
                }
            } message: {
                Text("The previous session ended unexpectedly. Would you like to open GitHub to submit a crash report? Your device info and crash details will be pre-filled.")
            }
        }
    }

    // MARK: - Crash Report Submission

    private func submitCrashReport() {
        let crashInfo = pendingCrashInfo ?? "No details captured."
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device  = UIDevice.current
        let body = """
        **Crash detected automatically on the previous app session.**

        \(crashInfo)

        ---
        **Device:** \(device.model)
        **iOS:** \(device.systemName) \(device.systemVersion)
        **App Version:** \(version) (\(build))
        """
        let repo = "xXKillerNoobYT/Weird-Part-Run-2"
        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title",  value: "[Crash] App crashed – auto-report"),
            URLQueryItem(name: "body",   value: body),
            URLQueryItem(name: "labels", value: "bug"),
        ]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
        CrashReporter.shared.clearPendingCrashReport()
        pendingCrashInfo = nil
    }
}
