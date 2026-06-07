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

    init() {
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

    private var shouldOpenTimesheetsForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI3041Timesheets")
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
                    } else if appCore.currentUser == nil {
                        LoginView()
                            .environmentObject(appCore)
                    } else if shouldOpenWarehouseSetupForUITest {
                        WarehouseOnboardingWizard()
                            .environmentObject(appCore)
                    } else if shouldOpenTimesheetsForUITest {
                        NavigationStack {
                            IOSTimesheetsPage()
                                .environmentObject(appCore)
                        }
                    } else if isAdmin && !hasCompletedCompanySetup {
                        CompanySetupWizard()
                            .environmentObject(appCore)
                    } else if onboardAIMVPEnabled && !hasSeenOnboardAIMVPEntry {
                        OnboardAIMVPEntryView()
                            .environmentObject(appCore)
                    } else if !hasCompletedOnboarding {
                        OnboardingWalkthroughView()
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
        }
    }
}
