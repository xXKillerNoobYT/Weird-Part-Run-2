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

    init() {
        // Existing users who already went through the app don't need the walkthrough or setup wizard
        if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
            if !UserDefaults.standard.bool(forKey: "hasCompletedCompanySetup") {
                UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")
            }
        }
    }

    /// True if the current user has admin-level permissions.
    private var isAdmin: Bool {
        appCore.hasPermission("manage_people") && appCore.hasPermission("manage_jobs")
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
                    if appCore.needsOnboarding {
                        OnboardingWelcomeView()
                            .environmentObject(appCore)
                    } else if appCore.needsBootstrap {
                        BootstrapView()
                            .environmentObject(appCore)
                    } else if appCore.currentUser == nil {
                        LoginView()
                            .environmentObject(appCore)
                    } else if isAdmin && !hasCompletedCompanySetup {
                        CompanySetupWizard()
                            .environmentObject(appCore)
                    } else if !hasCompletedOnboarding {
                        OnboardingWalkthroughView()
                            .environmentObject(appCore)
                    } else {
                        IOSMainView()
                            .environmentObject(appCore)
                            .environmentObject(tabPrefs)
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
