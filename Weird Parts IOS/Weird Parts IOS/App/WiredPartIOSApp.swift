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
    @AppStorage("firstLaunchSheetSeen") private var firstLaunchSheetSeen = false
    @AppStorage("onboarding_checklist_dismissed") private var checklistDismissed = false
    @State private var showFirstLaunchWelcome = false
    @State private var showFirstLaunchOptOutUndo = false
    @State private var firstLaunchWelcomeDismissReason = "dismiss"
    @State private var optOutUndoTask: Task<Void, Never>?

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
            .sheet(isPresented: $showFirstLaunchWelcome, onDismiss: markFirstLaunchSheetSeen) {
                FirstLaunchWelcomeSheet(
                    onStartSetup: startFirstLaunchSetup,
                    onExploreOnOwn: optOutOfFirstLaunchSetup
                )
            }
            .overlay(alignment: .bottom) {
                if showFirstLaunchOptOutUndo {
                    FirstLaunchOptOutToast {
                        undoFirstLaunchOptOut()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear(perform: presentFirstLaunchWelcomeIfNeeded)
            .onChange(of: appCore.isReady) { _, _ in
                presentFirstLaunchWelcomeIfNeeded()
            }
            .onChange(of: hasCompletedOnboarding) { _, _ in
                presentFirstLaunchWelcomeIfNeeded()
            }
            .onChange(of: hasCompletedCompanySetup) { _, _ in
                presentFirstLaunchWelcomeIfNeeded()
            }
        }
    }

    private var canPresentFirstLaunchWelcome: Bool {
        appCore.isReady &&
        (!ProcessInfo.processInfo.arguments.contains("-UITesting") ||
         ProcessInfo.processInfo.arguments.contains("-UITestingFirstLaunchOnboarding")) &&
        !appCore.needsOnboarding &&
        !appCore.needsBootstrap &&
        appCore.currentUser != nil &&
        !showFirstLaunchWelcome &&
        !firstLaunchSheetSeen &&
        hasCompletedCompanySetup &&
        hasCompletedOnboarding &&
        !onboardAIMVPEnabledOrPending
    }

    private var onboardAIMVPEnabledOrPending: Bool {
        onboardAIMVPEnabled && !hasSeenOnboardAIMVPEntry
    }

    private var isFirstLaunchState: Bool {
        guard let service = appCore.dashboardService else { return false }
        do {
            let kpi = try service.getKPISummary()
            return kpi.activeJobs == 0 &&
                kpi.partTypes == 0 &&
                kpi.totalStock == 0
        } catch {
            return false
        }
    }

    private func presentFirstLaunchWelcomeIfNeeded() {
        guard canPresentFirstLaunchWelcome, isFirstLaunchState else { return }
        showFirstLaunchWelcome = true
        recordOnboarding(.welcomeShown)
    }

    private func markFirstLaunchSheetSeen() {
        guard !firstLaunchSheetSeen else { return }
        let reason = firstLaunchWelcomeDismissReason
        firstLaunchWelcomeDismissReason = "dismiss"
        firstLaunchSheetSeen = true
        recordOnboarding(.welcomeDismissed, payload: ["reason": .string(reason)])
    }

    private func startFirstLaunchSetup() {
        firstLaunchWelcomeDismissReason = "startSetup"
        markFirstLaunchSheetSeen()
        checklistDismissed = false
        NotificationCenter.default.post(name: .onboardingScrollToChecklist, object: nil)
    }

    private func optOutOfFirstLaunchSetup() {
        firstLaunchWelcomeDismissReason = "exploreSelf"
        markFirstLaunchSheetSeen()
        checklistDismissed = true
        recordOnboarding(.cardDismissed, payload: [
            "reason": .string("exploreSelf"),
            "completedCount": .int(0),
        ])
        optOutUndoTask?.cancel()
        withAnimation {
            showFirstLaunchOptOutUndo = true
        }
        optOutUndoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showFirstLaunchOptOutUndo = false
            }
        }
    }

    private func undoFirstLaunchOptOut() {
        optOutUndoTask?.cancel()
        firstLaunchSheetSeen = false
        checklistDismissed = false
        recordOnboarding(.checklistRestarted, payload: ["source": .string("welcomeUndo")])
        withAnimation {
            showFirstLaunchOptOutUndo = false
        }
        NotificationCenter.default.post(name: .onboardingScrollToChecklist, object: nil)
    }

    private func recordOnboarding(_ event: OnboardingTelemetryService.EventType, payload: [String: TelemetryValue] = [:]) {
        try? appCore.onboardingTelemetryService?.record(event, payload: payload)
    }
}
