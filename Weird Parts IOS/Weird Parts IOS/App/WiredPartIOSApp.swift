import SwiftUI
import WiredPartCore

/// Main entry point for the WiredPart iOS application.
///
/// Initializes the shared AppCore (database + services) before
/// presenting any UI. On first launch the database is created
/// in the app's Documents directory; subsequent launches reopen it.
@main
struct WiredPartIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appCore = AppCore()
    @StateObject private var tabPrefs = TabBarPreferences()
    @State private var showLaunchErrorReport = false
    @State private var showUnreadableDatabaseRecoveryConfirmation = false
    @State private var isPreparingUnreadableDatabaseRecovery = false
    @State private var unreadableDatabaseRecoveryError: String?
    @State private var uiTestingPanelSchedule = PanelSchedule(
        panelName: "QA Panel A",
        panelType: .smallPanel,
        totalSpaces: 8,
        mainBreakerAmps: 200,
        voltage: 240,
        phase: 1,
        location: "Shop east wall",
        circuits: [
            CircuitEntry(
                spaceNumber: 1,
                breakerAmps: 20,
                breakerType: .single,
                circuitDescription: "Office lighting",
                isSpare: false,
                isFedFrom: "MDP"
            ),
            CircuitEntry(
                spaceNumber: 2,
                breakerAmps: 30,
                breakerType: .double,
                circuitDescription: "Compressor",
                isSpare: false
            ),
        ]
    )
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasCompletedCompanySetup") private var hasCompletedCompanySetup = false
    @AppStorage("hasSeenOnboardAIMVPEntry") private var hasSeenOnboardAIMVPEntry = false
    @AppStorage(OnboardAIFeatureFlag.onboardingMVP) private var onboardAIMVPEnabled = false

    init() {
        Self.migrateLegacyWelcomeFlags()
    }

    static func migrateLegacyWelcomeFlags(defaults: UserDefaults = .standard) {
        // One-time migration: users who already completed the old welcome flow
        // don't need to re-run the walkthrough or company-setup wizard.
        // Consume hasSeenWelcome immediately so this never re-fires on a
        // subsequent fresh build where the DB is empty but UserDefaults persisted.
        if defaults.bool(forKey: "hasSeenWelcome") {
            if !defaults.bool(forKey: "hasCompletedOnboarding") {
                defaults.set(true, forKey: "hasCompletedOnboarding")
            }
            if !defaults.bool(forKey: "hasCompletedCompanySetup") {
                defaults.set(true, forKey: "hasCompletedCompanySetup")
            }
            // Clear the trigger so a future fresh-DB build doesn't re-apply
            // these flags before bootstrap() can detect the empty database.
            defaults.removeObject(forKey: "hasSeenWelcome")
        }
    }

    /// True if the current user has admin-level permissions.
    private var isAdmin: Bool {
        appCore.hasPermission("manage_people") && appCore.hasPermission("manage_jobs")
    }

    /// Company setup creates first-device records. A device that paired with an
    /// existing business must skip it even if its local completion flag is false.
    static func shouldShowCompanySetup(
        isAdmin: Bool,
        hasCompletedCompanySetup: Bool,
        joinedExistingBusiness: Bool
    ) -> Bool {
        isAdmin && !hasCompletedCompanySetup && !joinedExistingBusiness
    }

    private var shouldOpenWarehouseSetupForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWarehouseSetupWizard")
    }

    private var shouldOpenTimesheetsForUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI3041Timesheets")
    }

    /// The AIFallback smoke needs the already-authenticated app shell on its
    /// first launch. Bootstrap seeds the fixture user and first-run defaults in
    /// the same pass, so ordinary production routing can otherwise render setup
    /// before SwiftUI observes those defaults.
    private var shouldOpenAuthenticatedShellForUITest: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting")
            && arguments.contains("-UITestingWEI936AutoLogin")
    }

    private var shouldShowWEI936WelcomeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI936Welcome")
    }

    private var shouldShowWEI936CelebrationFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI936Celebration")
    }

    #if DEBUG && targetEnvironment(simulator)
    private var shouldShowDevicePairingTransportErrorFixture: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting")
            && (arguments.contains("-UITestingDevicePairingTransportError")
                || arguments.contains("-UITestingDevicePairingNoTransportError"))
    }
    #else
    private var shouldShowDevicePairingTransportErrorFixture: Bool { false }
    #endif

    #if DEBUG && targetEnvironment(simulator)
    /// Deterministic launch failure for UI coverage of the pre-database report
    /// path. Requiring both flags prevents a stray argument from changing a
    /// normal debug launch, and the compile guard excludes this from devices.
    private var startupErrorUITestFixture: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITesting"),
              arguments.contains("-UITestingStartupErrorReport")
        else { return nil }
        return "UITest startup failure: OSStatus -25308"
    }
    #else
    private var startupErrorUITestFixture: String? { nil }
    #endif

    private var shouldOpenWEI3144MaterialsFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI3144JobMaterials")
    }

    private var shouldShowPanelScheduleFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingPanelScheduleBuilderFixture")
    }

    private var shouldShowAIFilterCommandFixture: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting")
            && arguments.contains("-UITestingAIFilterCommandFixture")
    }

    private var stage8ReportsUITestTarget: Stage8ReportsUITestTarget? {
        Stage8ReportsUITestTarget(processArguments: ProcessInfo.processInfo.arguments)
    }

    private var wei3988BackupRestoreUITestTarget: WEI3988BackupRestoreUITestTarget? {
        WEI3988BackupRestoreUITestTarget(processArguments: ProcessInfo.processInfo.arguments)
    }

    #if DEBUG
    private var shouldShowWEI3140ImportPreviewFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWEI3140ImportPreviewFixture")
    }
    #else
    private var shouldShowWEI3140ImportPreviewFixture: Bool {
        false
    }
    #endif

    /// Resolved color scheme from the user's theme setting.
    private var resolvedColorScheme: ColorScheme? {
        let processArguments = ProcessInfo.processInfo.arguments
        if processArguments.contains("-UITesting"),
           processArguments.contains("-UITestingAppearanceLight") {
            return .light
        }
        if processArguments.contains("-UITesting"),
           processArguments.contains("-UITestingAppearanceDark") {
            return .dark
        }

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

    private var unreadableDatabaseRecoveryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Database Needs Recovery")
                .font(.headline)
            Text("This device still has data, but it no longer has the encryption key needed to unlock it. The database has not been deleted or overwritten.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("To continue, keep this device near a trusted paired peer. The recovery action archives this unreadable database, then takes you to Join a Business so you can re-pair and download the company database again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let unreadableDatabaseRecoveryError {
                Text(unreadableDatabaseRecoveryError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                showUnreadableDatabaseRecoveryConfirmation = true
            } label: {
                if isPreparingUnreadableDatabaseRecovery {
                    ProgressView()
                } else {
                    Label("Archive and Re-pair", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPreparingUnreadableDatabaseRecovery)
            .accessibilityIdentifier("startup-unreadable-database-recovery-button")
            .accessibilityHint("Archives the unreadable encrypted database before opening the re-pairing flow.")
            Button("Report this startup problem") {
                showLaunchErrorReport = true
            }
            .buttonStyle(.bordered)
        }
        .confirmationDialog(
            "Archive the unreadable database?",
            isPresented: $showUnreadableDatabaseRecoveryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive and Continue to Re-pair", role: .destructive) {
                Task {
                    isPreparingUnreadableDatabaseRecovery = true
                    unreadableDatabaseRecoveryError = await appCore.archiveUnreadableDatabaseAndPrepareToRepair()
                    isPreparingUnreadableDatabaseRecovery = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This copies the unreadable database and its recovery files into local backups before clearing only the active copy. It cannot recover the missing key. Continue only when a trusted peer can provide a fresh download.")
        }
        .sheet(isPresented: $showLaunchErrorReport) {
            NavigationStack {
                ReportABugPage(
                    originModule: "Unreadable encrypted database",
                    launchError: appCore.loadError
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLaunchErrorReport = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    static func retryBootstrapOnActiveSceneTransition(
        phase: ScenePhase,
        retryBootstrap: () -> Void
    ) {
        guard phase == .active else { return }
        retryBootstrap()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldShowPanelScheduleFixture {
                    NavigationStack {
                        PanelScheduleBuilder(schedule: $uiTestingPanelSchedule) { saved in
                            uiTestingPanelSchedule = saved
                        }
                        .navigationTitle("Panel Schedule")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                } else if shouldShowAIFilterCommandFixture {
                    #if DEBUG
                    AIFilterCommandUITestFixtureHost()
                        .environmentObject(appCore)
                    #else
                    EmptyView()
                    #endif
                } else if shouldShowWEI3140ImportPreviewFixture {
                    #if DEBUG
                    WEI3140ImportPreviewFixtureView()
                    #else
                    EmptyView()
                    #endif
                } else if shouldShowDevicePairingTransportErrorFixture {
                    NavigationStack {
                        DevicePairingView()
                            .environmentObject(appCore)
                    }
                } else if let error = startupErrorUITestFixture {
                    startupErrorView(error: error)
                } else if appCore.isReady {
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
                    } else if appCore.needsInitialSync {
                        NavigationStack {
                            SyncWaitingView(canCancel: false)
                                .environmentObject(appCore)
                        }
                    } else if appCore.currentUser == nil {
                        LoginView()
                            .environmentObject(appCore)
                    } else if let wei3988BackupRestoreUITestTarget {
                        NavigationStack {
                            wei3988BackupRestoreUITestTarget.view(appCore: appCore)
                                .environmentObject(appCore)
                        }
                    } else if let stage8ReportsUITestTarget {
                        NavigationStack {
                            stage8ReportsUITestTarget.view(appCore: appCore)
                                .environmentObject(appCore)
                        }
                    } else if shouldOpenWEI3144MaterialsFixture,
                              let jobId = AppCore.uiTestingWEI3144JobMaterialsJobId(db: appCore.db) {
                        NavigationStack {
                            IOSJobDetailPage(jobId: jobId)
                                .environmentObject(appCore)
                        }
                    } else if shouldOpenWarehouseSetupForUITest {
                        WarehouseOnboardingWizard()
                            .environmentObject(appCore)
                    } else if shouldOpenTimesheetsForUITest {
                        NavigationStack {
                            IOSTimesheetsPage()
                                .environmentObject(appCore)
                        }
                    } else if shouldOpenAuthenticatedShellForUITest {
                        IOSMainView()
                            .environmentObject(appCore)
                            .environmentObject(tabPrefs)
                            .environmentObject(appCore.badgeCountManager)
                    } else if Self.shouldShowCompanySetup(
                        isAdmin: isAdmin,
                        hasCompletedCompanySetup: hasCompletedCompanySetup,
                        joinedExistingBusiness: appCore.joinedExistingBusiness
                    ) {
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
                } else if appCore.requiresUnreadableDatabaseRecovery {
                    unreadableDatabaseRecoveryView
                } else if let error = appCore.loadError {
                    startupErrorView(error: error)
                } else {
                    LoadingView()
                }
            }
            .preferredColorScheme(resolvedColorScheme)
            .tint(accentColor)
            .onChange(of: scenePhase) { _, phase in
                Self.retryBootstrapOnActiveSceneTransition(phase: phase) {
                    appCore.retryBootstrap()
                }
            }
        }
    }

    private func startupErrorView(error: String) -> some View {
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
            Button("Report this startup problem") {
                showLaunchErrorReport = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("startup-report-problem-button")
            .accessibilityHint("Opens the in-app bug report form with the startup error details.")
        }
        .sheet(isPresented: $showLaunchErrorReport) {
            NavigationStack {
                ReportABugPage(
                    originModule: "Startup",
                    launchError: error
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLaunchErrorReport = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }
}

private enum WEI3988BackupRestoreUITestTarget {
    case backups
    case partsCatalog
    case materials
    case preBilling
    case bookkeeper

    init?(processArguments: [String]) {
        guard processArguments.contains("-UITestingWEI3988BackupRestoreSmoke") else { return nil }
        if processArguments.contains("-UITestingWEI3988PartsCatalog") {
            self = .partsCatalog
        } else if processArguments.contains("-UITestingWEI3988Materials") {
            self = .materials
        } else if processArguments.contains("-UITestingWEI3988PreBilling") {
            self = .preBilling
        } else if processArguments.contains("-UITestingWEI3988Bookkeeper") {
            self = .bookkeeper
        } else {
            self = .backups
        }
    }

    @ViewBuilder
    func view(appCore: AppCore) -> some View {
        switch self {
        case .backups:
            IOSBackupsPage()
        case .partsCatalog:
            PartsRouter(tabId: "parts-catalog")
        case .materials:
            if let jobId = AppCore.uiTestingJobId(db: appCore.db, jobNumber: "UITEST-MAT-3144") {
                IOSJobDetailPage(jobId: jobId)
            } else {
                ContentUnavailableView("Restored job missing", systemImage: "exclamationmark.triangle")
            }
        case .preBilling:
            IOSPreBillingPage()
        case .bookkeeper:
            IOSBookkeeperExportPage()
        }
    }
}

private enum Stage8ReportsUITestTarget {
    case hub
    case preBilling
    case bookkeeper
    case auditSummary

    init?(processArguments: [String]) {
        guard processArguments.contains("-UITestingStage8Reports") else { return nil }
        if processArguments.contains("-UITestingStage8PreBilling") {
            self = .preBilling
        } else if processArguments.contains("-UITestingStage8Bookkeeper") {
            self = .bookkeeper
        } else if processArguments.contains("-UITestingStage8AuditSummary") {
            self = .auditSummary
        } else {
            self = .hub
        }
    }

    @ViewBuilder
    func view(appCore: AppCore) -> some View {
        switch self {
        case .hub:
            IOSReportsRouter(tabId: "reports-hub")
        case .preBilling:
            IOSPreBillingPage()
        case .bookkeeper:
            IOSBookkeeperExportPage()
        case .auditSummary:
            IOSAuditSummaryView(sessionId: AppCore.stage8ReportsUITestAuditSessionId(db: appCore.db) ?? 0)
        }
    }
}
