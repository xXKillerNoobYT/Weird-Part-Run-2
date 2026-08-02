import SwiftUI
import Combine
import WiredPartCore
import Security
import GRDB
import os.log

protocol AppCoreBackgroundTaskAuditing: Sendable {
    nonisolated func startTask(name: String, type: String, deviceId: String?) throws -> Int64
    nonisolated func completeTask(id: Int64, summary: String?, itemsProcessed: Int) throws
    nonisolated func failTask(id: Int64, error: String) throws
}

extension BackgroundTaskService: AppCoreBackgroundTaskAuditing {}

/// Shared application state that owns the database and all services.
///
/// Published as an `@EnvironmentObject` so every view in the tree
/// can access services and the current user without prop-drilling.
@MainActor
final class AppCore: ObservableObject {
    nonisolated private static let uiTestingLaunchFlag = "-UITesting"
    nonisolated private static let uiTestingPreserveDatabaseFlag = "-UITestingPreserveDatabase"
    nonisolated private static let localFallbackBootstrapKeyLock = NSLock()

    #if DEBUG && targetEnvironment(simulator)
    nonisolated private static let wei5134AIReadFailureFlag = "-UITestingWEI5134AIReadFailure"
    nonisolated private static let wei5159AIPrerequisiteRecoveryFlag = "-UITestingWEI5159AIPrerequisiteRecovery"
    nonisolated private static let wei5134AIConversationTable = "ai_conversation_messages"
    nonisolated private static let wei5134AIConversationBackupTable = "ai_conversation_messages_wei5134_backup"
    #endif

    // MARK: - Published State

    @Published var isReady = false
    @Published var loadError: String?
    @Published var needsBootstrap = false
    @Published var needsOnboarding = false
    @Published var currentUser: User?
    @Published var currentToken: String?
    @Published var permissions: [String] = []
    @Published var theme: SettingsService.ThemeSettings = .defaults

    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var wei5134AIReadFailureQAState = "WEI5134 QA table state: preparing"
    @Published private(set) var wei5159AIPrerequisiteQAState = "WEI5159 QA prerequisites: unavailable"
    @Published private(set) var wei5159AIPrerequisitesAvailable = false
    @Published private(set) var wei5159AIConversationListSuspended = false
    #endif

    // MARK: - Services (available after init completes)

    private(set) var db: AppDatabase?
    private(set) var authService: AuthService?
    private(set) var settingsService: SettingsService?
    public private(set) var partsService: PartsService?
    public private(set) var warehouseService: WarehouseService?
    public private(set) var jobsService: JobsService?
    public private(set) var ordersService: OrdersService?
    public private(set) var fleetService: FleetService?
    public private(set) var peopleService: PeopleService?
    public private(set) var schedulingService: SchedulingService?
    public private(set) var chatService: ChatService?
    public private(set) var notebooksService: NotebooksService?
    public private(set) var reportsService: ReportsService?
    public private(set) var toolsService: ToolsService?
    public private(set) var dashboardService: DashboardService?
    public private(set) var breakService: BreakService?
    public private(set) var jobEstimationService: JobEstimationService?
    public private(set) var dailyReportGenerator: DailyReportGenerator?
    public private(set) var wishlistService: WishlistService?
    public private(set) var backgroundTaskService: BackgroundTaskService?
    public private(set) var aiDispatchService: AIDispatchService?
    public private(set) var badgeCountService: BadgeCountService?

    /// Shared sync manager — all views observe this single instance.
    let syncManager = IOSSyncManager()

    /// Shared badge count manager — provides live pending-item counts for tab badges.
    let badgeCountManager = BadgeCountManager()

    /// Central registry for AI-activated page filters (prompt 62S).
    public let aiFilterRegistry = AIFilterRegistry()

    /// Guided onboarding progress tracker (per-user).
    @Published public var onboardingManager: OnboardingProgressManager?
    @Published public var onboardAIRuntimeBootstrap: OnboardAIRuntimeBootstrapResult?

    nonisolated let logger = Logger(subsystem: "com.wiredpart.ios", category: "AppCore")

    // MARK: - Lifecycle

    init() {
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    private var isUITestingMode: Bool {
        ProcessInfo.processInfo.arguments.contains(Self.uiTestingLaunchFlag)
    }

    private var shouldPreserveUITestDatabase: Bool {
        ProcessInfo.processInfo.arguments.contains(Self.uiTestingPreserveDatabaseFlag)
    }

    #if DEBUG && targetEnvironment(simulator)
    var isWEI5134AIReadFailureUITestingMode: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(Self.uiTestingLaunchFlag)
            && arguments.contains(Self.wei5134AIReadFailureFlag)
    }

    var isWEI5159AIPrerequisiteRecoveryUITestingMode: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(Self.uiTestingLaunchFlag)
            && arguments.contains(Self.wei5159AIPrerequisiteRecoveryFlag)
    }
    #endif

    /// Conversation-read prerequisites normally mirror the live app state. The
    /// simulator-only WEI-5159 mode can withhold only these read dependencies so
    /// the mounted assistant exercises startup/login recovery without signing out
    /// the shell or mutating production data.
    var aiConversationReadDatabase: AppDatabase? {
        #if DEBUG && targetEnvironment(simulator)
        if isWEI5159AIPrerequisiteRecoveryUITestingMode && !wei5159AIPrerequisitesAvailable {
            return nil
        }
        #endif
        return db
    }

    var aiConversationReadOwnerUserId: Int64? {
        #if DEBUG && targetEnvironment(simulator)
        if isWEI5159AIPrerequisiteRecoveryUITestingMode && !wei5159AIPrerequisitesAvailable {
            return nil
        }
        #endif
        return currentUser?.id
    }

    private func bootstrap() async {
        do {
            let uiTestingMode = isUITestingMode
            // Resolve the database path on the main actor (it accesses FileManager),
            // then perform all blocking database work off the main thread to avoid
            // priority inversion (user-interactive main thread waiting on
            // GRDB's default-QoS pool semaphore).
            let path = try Self.databasePath(isUITesting: uiTestingMode)
            if uiTestingMode && !shouldPreserveUITestDatabase {
                try Self.resetUITestDatabase(atPath: path)
            }
            if uiTestingMode && ProcessInfo.processInfo.arguments.contains("-UITestingWEI3988RestoreLatestBackup") {
                try Self.restoreLatestUITestBackup(toPath: path)
            }

            // NOTE: resetDatabaseIfNewBuild() was removed (GitHub #101).
            // It compared the binary's mod date and wiped the DB on every
            // Cmd+R rebuild. Clean builds already delete the simulator
            // sandbox, so migrations create tables from scratch naturally.
            let result = try await Task.detached(priority: .userInitiated) {
                let database: AppDatabase
                do {
// SQLCipher: derive a device-bound bootstrap key from the Keychain.
                    // This key never changes unless the Keychain is wiped (device reset).
                    // User PIN changes update authentication credentials only; the app DB
                    // stays on this device key so startup can always open it before login.
                    //
                    // Migration path: if the DB file is still plaintext (pre-SQLCipher binary),
                    // `migratePlaintextDBIfNeeded` converts it in-place before opening.
                    let keyHex = try Self.deviceBootstrapKeyHex()
                    database = try AppDatabase.openEncryptedDatabaseAfterReleaseMigration(
                        atPath: path,
                        keyHex: keyHex
                    )
                } catch {
                    #if DEBUG && targetEnvironment(simulator)
                    if Self.shouldResetLocalDatabaseAfterCipherOpenFailure(error) {
                        self.logger.warning(
                            "[AppCore] DEBUG SQLCipher open failed with decrypt/notadb; resetting local simulator database and retrying."
                        )
                        try DeviceResetService.deleteDatabaseStorage(atPath: path)
                        let keyHex = try Self.deviceBootstrapKeyHex()
                        database = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
                    } else {
                        throw error
                    }
                    #else
                    throw error
                    #endif
                }

                let auth = AuthService(db: database)
                let settings = SettingsService(db: database)
                if uiTestingMode {
                    try Self.seedUITestingFixtures(db: database, authService: auth)
                }

                let theme = try? settings.getTheme()
                let users = try auth.getActiveUsers()
                let hasProfile = try settings.hasBusinessProfile()

                return (
                    database: database,
                    auth: auth,
                    settings: settings,
                    parts: PartsService(db: database, auth: auth),
                    warehouse: WarehouseService(db: database),
                    jobs: JobsService(db: database),
                    orders: OrdersService(db: database),
                    fleet: FleetService(db: database, auth: auth),
                    people: PeopleService(db: database),
                    scheduling: SchedulingService(db: database),
                    chat: ChatService(db: database),
                    notebooks: NotebooksService(db: database, auth: auth),
                    reports: ReportsService(db: database),
                    tools: ToolsService(db: database),
                    dashboard: DashboardService(db: database),
                    breaks: BreakService(db: database),
                    jobEstimation: JobEstimationService(db: database),
                    dailyReport: DailyReportGenerator(db: database),
                    wishlist: WishlistService(db: database, auth: auth),
                    backgroundTask: BackgroundTaskService(db: database),
                    aiDispatch: AIDispatchService(db: database),
                    badgeCount: BadgeCountService(db: database),
                    theme: theme,
                    users: users,
                    hasProfile: hasProfile
                )
            }.value

            // Apply results back on MainActor
            db = result.database
            #if DEBUG && targetEnvironment(simulator)
            if isWEI5134AIReadFailureUITestingMode {
                wei5134AIReadFailureQAState = "WEI5134 QA table state: table broken"
            }
            #endif
            authService = result.auth
            settingsService = result.settings
            partsService = result.parts
            warehouseService = result.warehouse
            jobsService = result.jobs
            ordersService = result.orders
            fleetService = result.fleet
            peopleService = result.people
            schedulingService = result.scheduling
            chatService = result.chat
            notebooksService = result.notebooks
            reportsService = result.reports
            toolsService = result.tools
            dashboardService = result.dashboard
            breakService = result.breaks
            jobEstimationService = result.jobEstimation
            dailyReportGenerator = result.dailyReport
            wishlistService = result.wishlist
            backgroundTaskService = result.backgroundTask
            aiDispatchService = result.aiDispatch
            badgeCountService = result.badgeCount

            if let theme = result.theme {
                self.theme = theme
            }

            if result.users.isEmpty && !result.hasProfile {
                // Brand-new device — show two-path onboarding.
                // Clear stale UserDefaults flags so a fresh-build DB doesn't
                // inherit "already completed" flags from a previous install.
                UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                UserDefaults.standard.removeObject(forKey: "hasCompletedCompanySetup")
                UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
                needsOnboarding = true
                needsBootstrap = false
            } else if result.users.isEmpty && result.hasProfile {
                // Business profile exists but no admin yet (edge case)
                needsBootstrap = true
                needsOnboarding = false
            } else {
                needsBootstrap = false
                needsOnboarding = false
            }

            let uiTestDisplayName = ProcessInfo.processInfo.arguments.contains("-UITestingTeamsViewOnly")
                ? "UITest People Viewer"
                : "UITest Owner"
            if uiTestingMode &&
               ProcessInfo.processInfo.arguments.contains("-UITestingWEI936AutoLogin") &&
               !ProcessInfo.processInfo.arguments.contains("-UITestingForceLogin"),
               let uiTestUser = result.users.first(where: { $0.displayName == uiTestDisplayName }),
               let userId = uiTestUser.id {
                currentUser = uiTestUser
                permissions = (try? result.auth.getUserPermissions(userId)) ?? []
                onboardingManager = OnboardingProgressManager(userId: userId)
                badgeCountManager.setUserId(userId)
            }
            isReady = true
            await evaluateOnboardAIRuntimeIfEnabled()

            // Configure badge count manager
            if let badgeService = badgeCountService {
                badgeCountManager.configure(service: badgeService, userId: currentUser?.id)
            }

            // Configure sync manager now that DB + settings are ready
            if let database = db, let settings = settingsService {
                syncManager.configure(db: database, settingsService: settings)

                // Set up app lifecycle sync (foreground resume)
                syncManager.setupAppLifecycleSync()

                // Auto-sync on launch if configured
                if syncManager.isSyncAvailable && syncManager.isAutoSyncEnabled {
                    Task { [syncManager] in
                        await syncManager.syncNow()
                        syncManager.startPeerDiscovery()

                        // Start periodic sync at the configured interval
                        let intervalStr = (try? settings.getSettingsByCategory("sync"))?["sync_interval"] ?? "60"
                        let interval = TimeInterval(intervalStr) ?? 60
                        syncManager.startAutoSync(intervalSeconds: max(interval, 15))
                    }
                }
            }

            // Clean up stale background tasks from previous sessions
            Task.detached { [backgroundTaskService] in
                _ = try? backgroundTaskService?.cleanupStaleTasks()
                _ = try? backgroundTaskService?.cleanupOldEntries()
            }

            // Run scheduled Tools maintenance on launch so expired trades and
            // confidence-score decay are handled even when users do not open a tool detail page.
            Task.detached { [toolsService, backgroundTaskService, logger] in
                Self.runAuditedBootstrapTask(
                    name: "Tools Scheduled Maintenance",
                    type: "tools_maintenance",
                    backgroundTaskService: backgroundTaskService,
                    logger: logger
                ) {
                    let result = try toolsService?.runScheduledMaintenance()
                    let expiredTrades = result?.expiredTrades ?? 0
                    let updatedScores = result?.updatedConfidenceScores ?? 0
                    return "Expired \(expiredTrades) trade(s); updated \(updatedScores) confidence score(s)"
                }
            }

            // Run companion auto-discovery cycle in the background (logged)
            Task.detached { [partsService, backgroundTaskService, logger] in
                Self.runAuditedBootstrapTask(
                    name: "Companion Auto-Discovery",
                    type: "companion_discovery",
                    backgroundTaskService: backgroundTaskService,
                    logger: logger
                ) {
                    try partsService?.runAutoDiscoveryCycle()
                    return "Discovery cycle completed"
                }
            }

            // Ensure Office chat channel exists (auto-created system channel)
            Task.detached { [chatService, backgroundTaskService, logger] in
                Self.runAuditedBootstrapTask(
                    name: "Office Channel Setup",
                    type: "system_setup",
                    backgroundTaskService: backgroundTaskService,
                    logger: logger
                ) {
                    try chatService?.ensureOfficeChannel()
                    return "Office channel ready"
                }
            }

            // Migrate legacy tmp-absolute chat attachment paths into durable,
            // backup-excluded Application Support storage (#1371). Surviving files
            // are copied and rewritten to relative paths; purged files are left to
            // render as "file unavailable" (#1372). One-shot, idempotent.
            Task.detached { [chatService, backgroundTaskService, logger] in
                Self.runAuditedBootstrapTask(
                    name: "Chat Attachment Path Migration",
                    type: "system_setup",
                    backgroundTaskService: backgroundTaskService,
                    logger: logger
                ) {
                    let storage = try AttachmentStorage()
                    let migrated = try chatService?.reconcileLegacyAttachmentPaths(storage: storage) ?? 0
                    return "Reconciled \(migrated) attachment path(s)"
                }
            }
        } catch {
            let nsError = error as NSError
            logger.error(
                "[AppCore] bootstrap failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(error.localizedDescription, privacy: .public)"
            )
            loadError = userFriendlyError(error, context: "start app")
            BugReportErrorLog.shared.record(loadError, context: "App startup")
        }
    }

    /// Retry bootstrap after a failure.
    func retryBootstrap() {
        loadError = nil
        Task { @MainActor in
            await bootstrap()
        }
    }

    nonisolated static func isRecoverableDebugCipherOpenFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.code == 26 else { return false }

        let description = error.localizedDescription.lowercased()
        return description.contains("file is not a database")
            || description.contains("not a database")
            || description.contains("decrypt")
    }

    nonisolated static func shouldResetLocalDatabaseAfterCipherOpenFailure(_ error: Error) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        return isRecoverableDebugCipherOpenFailure(error)
        #else
        return false
        #endif
    }


    // MARK: - Auth Actions

    /// Authenticate a user by PIN and store the session.
    func login(userId: Int64, pin: String) async -> String? {
        guard let authService else { return "App not ready. Please wait." }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let authResult = try authService.authenticateByPin(userId: userId, pin: pin)
                var perms: [String] = []
                if authResult.success, let uid = authResult.user?.id {
                    perms = try authService.getUserPermissions(uid)
                }
                return (auth: authResult, permissions: perms)
            }.value

            if result.auth.success {
                currentUser = result.auth.user
                currentToken = result.auth.token
                permissions = result.permissions
                if let userId = result.auth.user?.id {
                    onboardingManager = OnboardingProgressManager(userId: userId)
                    badgeCountManager.setUserId(userId)
                }
                return nil // no error
            } else {
                return result.auth.message
            }
        } catch {
            return userFriendlyError(error, context: "start app")
        }
    }

    /// Log out the current user and return to the login screen.
    func logout() {
        currentUser = nil
        currentToken = nil
        permissions = []
        onboardingManager = nil
        badgeCountManager.setUserId(nil)
        // Drop any unconsumed QR quick-action context so it cannot leak into
        // the next user's session on a shared device (#700).
        QRScanRouteStore.shared.clearAll()
        NotificationCenter.default.post(name: .appDidLogout, object: self)
    }

    /// Run the first-device bootstrap, creating the admin user and default data.
    func seedFirstAdmin(displayName: String, pin: String) async -> String? {
        guard let authService else { return "App not ready. Please wait." }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let seedResult = try authService.seedFirstAdmin(displayName: displayName, pin: pin)
                var perms: [String] = []
                if seedResult.success, let uid = seedResult.user?.id {
                    perms = try authService.getUserPermissions(uid)
                }
                return (seed: seedResult, permissions: perms)
            }.value

            if result.seed.success {
                currentUser = result.seed.user
                currentToken = result.seed.token
                needsBootstrap = false
                permissions = result.permissions
                if let userId = result.seed.user?.id {
                    onboardingManager = OnboardingProgressManager(userId: userId)
                    badgeCountManager.setUserId(userId)
                }
                return nil
            } else {
                return result.seed.message
            }
        } catch {
            return userFriendlyError(error, context: "start app")
        }
    }

    /// Finish onboarding and transition to the main app (or login screen).
    func completeOnboarding() {
        needsOnboarding = false
        // If seedFirstAdmin was called during onboarding, currentUser is set
        // and the app will go straight to IOSMainView.
        // If joining an existing business (sync path), currentUser is nil
        // and the app will show LoginView.
    }

    /// Check if the current user has a specific permission.
    func hasPermission(_ key: String) -> Bool {
        permissions.contains(key)
    }

    private func evaluateOnboardAIRuntimeIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: OnboardAIFeatureFlag.onboardingMVP) else {
            onboardAIRuntimeBootstrap = nil
            return
        }

        let startedAt = Date()
        let bootstrapper = OnboardAIRuntimeBootstrapper()
        let result = await bootstrapper.bootstrap()
        onboardAIRuntimeBootstrap = result

        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        logger.info(
            "[OnboardAI] bootstrap route=\(result.route.rawValue, privacy: .public) latency_ms=\(latencyMs, privacy: .public) availability=\(result.availabilityLabel, privacy: .public) timeout_budget_ms=\(result.timeoutBudgetMs, privacy: .public) did_timeout=\(result.didTimeout, privacy: .public) fallback_model_unavailable=\(result.usedModelUnavailableFallback, privacy: .public) fallback_low_resource=\(result.usedLowResourceFallback, privacy: .public)"
        )
    }

    nonisolated static func runAuditedBootstrapTask(
        name: String,
        type: String,
        backgroundTaskService: AppCoreBackgroundTaskAuditing?,
        logger: Logger,
        operation: @Sendable () throws -> String
    ) {
        var taskId: Int64?

        if let backgroundTaskService {
            do {
                taskId = try backgroundTaskService.startTask(
                    name: name,
                    type: type,
                    deviceId: nil
                )
            } catch {
                let nsError = error as NSError
                logger.error("[AppCore] Failed to start background task audit record task_name=\(name, privacy: .public) task_type=\(type, privacy: .public) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            }
        }

        let successSummary: String
        do {
            successSummary = try operation()
        } catch {
            let nsError = error as NSError
            logger.error("[AppCore] Bootstrap background task failed task_name=\(name, privacy: .public) task_type=\(type, privacy: .public) error=\(error.localizedDescription, privacy: .private) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public)")
            guard let taskId, let backgroundTaskService else { return }

            do {
                try backgroundTaskService.failTask(id: taskId, error: error.localizedDescription)
            } catch {
                let nsError = error as NSError
                logger.error("[AppCore] Failed to mark background task audit record as failed task_name=\(name, privacy: .public) task_type=\(type, privacy: .public) task_id=\(taskId, privacy: .public) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            }
            return
        }

        guard let taskId, let backgroundTaskService else { return }
        do {
            try backgroundTaskService.completeTask(
                id: taskId,
                summary: successSummary,
                itemsProcessed: 0
            )
        } catch {
            let nsError = error as NSError
            logger.error("[AppCore] Failed to complete background task audit record task_name=\(name, privacy: .public) task_type=\(type, privacy: .public) task_id=\(taskId, privacy: .public) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
        }
    }

    /// Reload theme settings from the database and apply them.
    func updateTheme() {
        if let settings = settingsService {
            self.theme = (try? settings.getTheme()) ?? .defaults
        }
    }

    // MARK: - Database Reset

    /// Delete all local data and return to the bootstrap screen.
    ///
    /// Flow:
    /// 1. Deactivate this device in the local registry (so peers know)
    /// 2. Release all service references (closes DB connections)
    /// 3. Delete the SQLite file + WAL + SHM
    /// 4. Clear saved session
    /// 5. Re-bootstrap (creates fresh DB → no users → needsBootstrap)
    func performDatabaseReset() async throws {
        let dbPath = try Self.databasePath()

        // 1. Deactivate this device in the registry before wiping
        if let database = self.db {
            let resetService = DeviceResetService(db: database)
            try? resetService.deactivateCurrentDevice()
        }

        // 2. Release all services and database connection
        authService = nil
        settingsService = nil
        partsService = nil
        warehouseService = nil
        jobsService = nil
        ordersService = nil
        fleetService = nil
        peopleService = nil
        schedulingService = nil
        chatService = nil
        notebooksService = nil
        reportsService = nil
        toolsService = nil
        dashboardService = nil
        breakService = nil
        jobEstimationService = nil
        dailyReportGenerator = nil
        wishlistService = nil
        backgroundTaskService = nil
        aiDispatchService = nil
        badgeCountService = nil
        db = nil

        // 3. Delete the database files and local backups
        try DeviceResetService.deleteDatabaseStorage(atPath: dbPath)

        // 4. Clear saved session and app-scoped UserDefaults state so reset
        //    cannot inherit drafts, sync flags, or onboarding progress.
        currentUser = nil
        currentToken = nil
        permissions = []
        onboardingManager = nil
        onboardAIRuntimeBootstrap = nil
        badgeCountManager.setUserId(nil)
        DeviceResetService.clearSavedAppState()

        // 5. Re-bootstrap — will detect no users/profile and set needsOnboarding = true
        isReady = false
        needsBootstrap = false
        needsOnboarding = false
        loadError = nil
        await bootstrap()
    }

    // MARK: - Debug Build Detection

    // resetDatabaseIfNewBuild() removed — see GitHub #101.
    // The function compared binary mod dates and wiped the DB on every
    // Cmd+R, making data persistence impossible during development.

    // MARK: - SQLCipher Device Bootstrap Key

    /// Return the device-bound SQLCipher bootstrap key (hex-encoded 64 chars).
    ///
    /// This key is used exclusively to encrypt the database file. It is a random
    /// 32-byte value generated on first launch and stored in the Keychain with
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It never changes.
    ///
    /// User PIN changes do not re-key the app database. Startup must open the DB
    /// before any user can enter a PIN, so the persistent DB key remains device-bound.
    nonisolated struct BootstrapKeychainAccess: Sendable {
        let read: @Sendable () -> (status: OSStatus, data: Data?)
        let add: @Sendable (Data) -> OSStatus
        let delete: @Sendable () -> OSStatus

        static let live = BootstrapKeychainAccess(
            read: {
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: "com.wiredpart.dbcipher.bootstrap-key",
                    kSecAttrAccount: "device-bootstrap-key",
                    kSecReturnData: true,
                    kSecMatchLimit: kSecMatchLimitOne
                ]
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result as? Data)
            },
            add: { keyData in
                var query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: "com.wiredpart.dbcipher.bootstrap-key",
                    kSecAttrAccount: "device-bootstrap-key",
                    kSecValueData: keyData
                ]
                #if !targetEnvironment(macCatalyst)
                query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                #endif
                return SecItemAdd(query as CFDictionary, nil)
            },
            delete: {
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: "com.wiredpart.dbcipher.bootstrap-key",
                    kSecAttrAccount: "device-bootstrap-key"
                ]
                return SecItemDelete(query as CFDictionary)
            }
        )
    }

    nonisolated static func deviceBootstrapKeyHex(
        processArguments: [String] = ProcessInfo.processInfo.arguments,
        keychain: BootstrapKeychainAccess = .live,
        fallbackDirectory: URL? = nil
    ) throws -> String {
        let uiTestingLaunchFlag = "-UITesting"
        let uiTestingDatabaseKeyHex = "8f1df32f4be04d5fcde1e8e6ddf9187f53a4b68370d5aafc56f0d43f2e9732a1"
        if processArguments.contains(uiTestingLaunchFlag) {
            return uiTestingDatabaseKeyHex
        }

        let readResult = keychain.read()
        if readResult.status == errSecSuccess, let data = readResult.data, data.count == 32 {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        if shouldUseLocalBootstrapKeyFallback(for: readResult.status) {
            return try localFallbackBootstrapKeyHex(in: fallbackDirectory)
        }
        if readResult.status == errSecSuccess {
            // Self-heal legacy/corrupt entries before minting a replacement key.
            _ = keychain.delete()
        } else if readResult.status != errSecItemNotFound {
            throw CipherKeyError.keychainAccessFailed(readResult.status)
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard rc == errSecSuccess else {
            throw CipherKeyError.bootstrapKeyGenerationFailed(rc)
        }
        let keyData = Data(keyBytes)

        let addStatus = keychain.add(keyData)
        if addStatus == errSecSuccess {
            return keyData.map { String(format: "%02x", $0) }.joined()
        }
        if shouldUseLocalBootstrapKeyFallback(for: addStatus) {
            return try localFallbackBootstrapKeyHex(in: fallbackDirectory)
        }
        if addStatus == errSecDuplicateItem {
            let rereadResult = keychain.read()
            if rereadResult.status == errSecSuccess, let data = rereadResult.data, data.count == 32 {
                return data.map { String(format: "%02x", $0) }.joined()
            }
            if shouldUseLocalBootstrapKeyFallback(for: rereadResult.status) {
                return try localFallbackBootstrapKeyHex(in: fallbackDirectory)
            }
            // Preserve the existing recovery path for a stale duplicate entry.
            _ = keychain.delete()
            let retryAddStatus = keychain.add(keyData)
            if retryAddStatus == errSecSuccess {
                return keyData.map { String(format: "%02x", $0) }.joined()
            }
            if shouldUseLocalBootstrapKeyFallback(for: retryAddStatus) {
                return try localFallbackBootstrapKeyHex(in: fallbackDirectory)
            }
            throw CipherKeyError.keychainAccessFailed(retryAddStatus)
        }
        throw CipherKeyError.keychainAccessFailed(addStatus)
    }

    nonisolated static func shouldUseLocalBootstrapKeyFallback(for status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    nonisolated static func localFallbackBootstrapKeyURL(in directory: URL? = nil) throws -> URL {
        let parent: URL
        if let directory {
            parent = directory
        } else if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            parent = supportURL.appendingPathComponent("WiredPart", isDirectory: true)
        } else {
            throw AppCoreError.noDocumentsDirectory
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent.appendingPathComponent("local-bootstrap-key.bin")
    }

    /// Persistent bootstrap-key fallback for approved keychain-unavailable states.
    /// The key stays in the app container and is excluded from device/iCloud backups.
    nonisolated static func localFallbackBootstrapKeyHex(in directory: URL? = nil) throws -> String {
        localFallbackBootstrapKeyLock.lock()
        defer { localFallbackBootstrapKeyLock.unlock() }

        let keyURL = try localFallbackBootstrapKeyURL(in: directory)
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            try excludeLocalFallbackBootstrapKeyFromBackup(at: keyURL)
            return data.map { String(format: "%02x", $0) }.joined()
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard rc == errSecSuccess else {
            throw CipherKeyError.bootstrapKeyGenerationFailed(rc)
        }
        let keyData = Data(keyBytes)
        try keyData.write(to: keyURL, options: .atomic)
        try excludeLocalFallbackBootstrapKeyFromBackup(at: keyURL)
        return keyData.map { String(format: "%02x", $0) }.joined()
    }

    /// Applies the fallback key's backup-exclusion requirement every time the
    /// persisted key is used. A metadata-write failure is intentionally surfaced:
    /// returning an unprotected persistent database key would weaken the fallback.
    nonisolated private static func excludeLocalFallbackBootstrapKeyFromBackup(at keyURL: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = keyURL
        try mutableURL.setResourceValues(values)
    }

    nonisolated static func deleteLocalFallbackBootstrapKey(in directory: URL? = nil) throws {
        let keyURL = try localFallbackBootstrapKeyURL(in: directory)
        guard FileManager.default.fileExists(atPath: keyURL.path) else { return }
        try FileManager.default.removeItem(at: keyURL)
    }

    // MARK: - PIN Change

    /// Change a user's PIN (hash only — does not re-key the database).
    ///
    /// The SQLCipher database remains encrypted with the device bootstrap key.
    /// Re-keying to a per-user PIN would require a pre-open unlock flow on startup,
    /// which this app does not have.
    ///
    /// - Parameters:
    ///   - userId: The ID of the authenticated user.
    ///   - oldPin: The current PIN (verified before update runs).
    ///   - newPin: The replacement PIN (4–8 digits).
    /// - Returns: nil on success, or a user-friendly error string.
    func changePin(userId: Int64, oldPin: String, newPin: String) async -> String? {
        guard let authService else { return "App not ready. Please wait." }
        do {
            // changePin returns Bool; success is signaled by not throwing, so the
            // returned value is intentionally discarded.
            _ = try await Task.detached(priority: .userInitiated) {
                try authService.changePin(userId: userId, oldPin: oldPin, newPin: newPin)
            }.value
            return nil
        } catch {
            return userFriendlyError(error, context: "change PIN")
        }
    }


    enum AppCoreError: LocalizedError {
        case noDocumentsDirectory

        var errorDescription: String? {
            switch self {
            case .noDocumentsDirectory:
                return "Unable to locate app storage directory. Please restart the app."
            }
        }
    }

    enum UITestBootstrapError: LocalizedError {
        case partCategoryMissing
        case fixturePartMissing(String)
        #if DEBUG && targetEnvironment(simulator)
        case wei5134MissingOwner
        case wei5159MissingOwner
        case aiConversationFixtureInvalidTableTopology(currentExists: Bool, backupExists: Bool)
        #endif

        var errorDescription: String? {
            switch self {
            case .partCategoryMissing:
                "UI test bootstrap failed because the required active part category fixture is missing."
            case .fixturePartMissing(let code):
                "UI test bootstrap failed because the required active part fixture \(code) is missing."
            #if DEBUG && targetEnvironment(simulator)
            case .wei5134MissingOwner:
                "WEI-5134 UI test bootstrap requires the deterministic UITest Owner."
            case .wei5159MissingOwner:
                "WEI-5159 UI test bootstrap requires the deterministic UITest Owner."
            case let .aiConversationFixtureInvalidTableTopology(currentExists, backupExists):
                "AI conversation UI-test fixture table topology is invalid (current: \(currentExists), backup: \(backupExists))."
            #endif
            }
        }
    }

    /// Returns the path to the SQLite database file in the app's documents directory.
    /// On iOS this is the sandboxed Documents folder.
    nonisolated static func databasePath() throws -> String {
        try databasePath(isUITesting: false)
    }

    nonisolated static func databasePath(isUITesting: Bool) throws -> String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppCoreError.noDocumentsDirectory
        }
        let dir = docs.appendingPathComponent("WiredPart")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = isUITesting ? "wiredpart-uitesting.sqlite" : "wiredpart.sqlite"
        return dir.appendingPathComponent(filename).path
    }

    nonisolated private static func resetUITestDatabase(atPath path: String) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = path + suffix
            if fm.fileExists(atPath: file) {
                try fm.removeItem(atPath: file)
            }
        }
    }

    nonisolated private static func restoreLatestUITestBackup(toPath path: String) throws {
        let fm = FileManager.default
        let backupDir = (path as NSString).deletingLastPathComponent + "/Backups"
        guard fm.fileExists(atPath: backupDir) else { return }
        let backupFiles = try fm.contentsOfDirectory(atPath: backupDir)
            .filter { $0.hasPrefix("wiredpart-backup-") && $0.hasSuffix(".sqlite") }
            .sorted()
        guard let latest = backupFiles.last else { return }
        let backupPath = backupDir + "/" + latest
        try AppDatabase.restoreDatabase(from: backupPath, to: path)
    }

    nonisolated static func seedUITestingFixtures(db: AppDatabase, authService: AuthService) throws {
        let seedResult = try authService.seedFirstAdmin(displayName: "UITest Owner", pin: "1234")
        let activeUsers = try authService.getActiveUsers()
        let fixtureUserId = seedResult.user?.id ??
            activeUsers.first(where: { $0.displayName == "UITest Owner" })?.id ??
            activeUsers.first?.id

        if ProcessInfo.processInfo.arguments.contains("-UITestingTeamsViewOnly") {
            let viewerUserId: Int64
            if let existingViewerUserId = activeUsers.first(where: { $0.displayName == "UITest People Viewer" })?.id {
                viewerUserId = existingViewerUserId
            } else {
                viewerUserId = try authService.createUser(displayName: "UITest People Viewer", pin: "2468")
            }
            try db.writer.write { dbConn in
                try dbConn.execute(sql: """
                    INSERT OR IGNORE INTO hats (name, description, level, is_builtin)
                    VALUES ('UITest People Viewer', 'UI-test-only view_people role', 0, 0)
                    """)
                guard let viewerHatId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM hats WHERE name = 'UITest People Viewer'"
                ) else { return }
                try dbConn.execute(
                    sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, 'view_people')",
                    arguments: [viewerHatId]
                )
                try dbConn.execute(sql: """
                    UPDATE user_hats
                    SET is_active = 0,
                        deleted_at = COALESCE(deleted_at, datetime('now'))
                    WHERE user_id = ?
                      AND hat_id != ?
                      AND (is_active = 1 OR deleted_at IS NULL)
                    """, arguments: [viewerUserId, viewerHatId])
                try dbConn.execute(sql: """
                    INSERT INTO user_hats (user_id, hat_id, is_active, deleted_at)
                    VALUES (?, ?, 1, NULL)
                    ON CONFLICT(user_id, hat_id) DO UPDATE SET
                        is_active = 1,
                        deleted_at = NULL
                    """, arguments: [viewerUserId, viewerHatId])

                try dbConn.execute(sql: """
                    INSERT INTO employee_teams
                        (name, description, is_active, created_by, updated_by, deleted_at)
                    VALUES ('UITest Read Only Team', 'Permission regression fixture', 1, ?, ?, NULL)
                    ON CONFLICT(name) DO UPDATE SET
                        description = excluded.description,
                        is_active = 1,
                        updated_by = excluded.updated_by,
                        updated_at = datetime('now'),
                        deleted_at = NULL
                    """, arguments: [fixtureUserId, fixtureUserId])
                guard let teamId = try Int64.fetchOne(
                    dbConn,
                    sql: """
                        SELECT id FROM employee_teams
                        WHERE name = 'UITest Read Only Team' AND is_active = 1 AND deleted_at IS NULL
                        """
                ) else { return }
                try dbConn.execute(sql: """
                    INSERT INTO employee_team_members
                        (team_id, user_id, role, added_by, deleted_at)
                    VALUES (?, ?, 'member', ?, NULL)
                    ON CONFLICT(team_id, user_id) DO UPDATE SET
                        role = excluded.role,
                        joined_at = datetime('now'),
                        deleted_at = NULL,
                        added_by = excluded.added_by,
                        removed_by = NULL
                    """, arguments: [teamId, viewerUserId, fixtureUserId])
            }
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let longNotesLocal = String(repeating: "LOCAL_NOTES_SEGMENT_", count: 22)
        let longNotesRemote = String(repeating: "REMOTE_NOTES_SEGMENT_", count: 22)
        let priorityLocal = String(repeating: "LOCAL_PRIORITY_", count: 10)
        let priorityRemote = String(repeating: "REMOTE_PRIORITY_", count: 10)

        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _conflict_log")
            try dbConn.execute(
                sql: """
                    INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value, winner, local_device, remote_device, local_ts, remote_ts, reviewed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: ["jobs", "1001", "notes", longNotesLocal, longNotesRemote, "local", "UITEST-LOCAL", "UITEST-REMOTE", now, now]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value, winner, local_device, remote_device, local_ts, remote_ts, reviewed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: ["jobs", "1002", "priority_label", priorityLocal, priorityRemote, "remote", "UITEST-LOCAL", "UITEST-REMOTE", now, now]
            )
            // WEI-1752 / WEI-881 QA fixture: the -UITesting runtime must expose a
            // selectable active job, at least one category, and a deterministic JPO
            // with 2+ selectable line items so the bulk hold/chat smoke can run
            // without manual simulator database surgery.
            //
            // -UITestingWEI936NotStarted opts out of this seeding to produce a true
            // zero-data first-launch state where isFirstLaunchState == true, so the
            // Dashboard Getting Started checklist is visible for C10 QA captures.
            if let userId = fixtureUserId,
               !ProcessInfo.processInfo.arguments.contains("-UITestingWEI936NotStarted") {
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO part_categories
                        (name, description, sort_order, is_active, created_at, updated_at)
                        VALUES ('UITesting Electrical', 'Deterministic UI smoke fixture category', 0, 1, datetime('now'), datetime('now'))
                        """
                )
                try dbConn.execute(
                    sql: """
                        UPDATE part_categories
                        SET is_active = 1, deleted_at = NULL, updated_at = datetime('now')
                        WHERE name = 'UITesting Electrical'
                        """
                )
                guard let categoryId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM part_categories WHERE name = 'UITesting Electrical' AND deleted_at IS NULL AND is_active = 1"
                ) else {
                    throw UITestBootstrapError.partCategoryMissing
                }

                let fixtureParts: [(id: Int64, code: String, name: String, description: String)] = [
                    (900_001, "UITEST-QA-CONDUIT", "UITesting QA Conduit", "Selectable conduit line for bulk JPO hold QA"),
                    (900_002, "UITEST-QA-WIRE", "UITesting QA Wire", "Selectable wire line for bulk JPO hold QA")
                ]
                for part in fixtureParts {
                    try dbConn.execute(
                        sql: """
                            INSERT OR IGNORE INTO parts
                            (id, category_id, part_type, code, name, description, unit_of_measure,
                             company_cost_price, company_markup_percent, is_active, deleted_at,
                             created_at, updated_at)
                            VALUES (?, ?, 'general', ?, ?, ?, 'each', 1.0, 0.0, 1, NULL, datetime('now'), datetime('now'))
                            """,
                        arguments: [part.id, categoryId, part.code, part.name, part.description]
                    )
                    try dbConn.execute(
                        sql: """
                            UPDATE parts
                            SET category_id = ?, name = ?, description = ?, unit_of_measure = 'each',
                                is_active = 1, deleted_at = NULL, updated_at = datetime('now')
                            WHERE code = ?
                            """,
                        arguments: [categoryId, part.name, part.description, part.code]
                    )
                }

                // The critical conflict must reference a real row and a real
                // synced column. The previous synthetic parts #2001/unit_cost
                // pair matched neither, so choosing the local loser failed while
                // choosing the already-applied remote winner appeared to work.
                guard let conflictPartId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM parts WHERE code = 'UITEST-QA-CONDUIT' AND is_active = 1 AND deleted_at IS NULL"
                ) else {
                    throw UITestBootstrapError.fixturePartMissing("UITEST-QA-CONDUIT")
                }
                try dbConn.execute(
                    sql: "UPDATE parts SET company_cost_price = 21.90 WHERE id = ?",
                    arguments: [conflictPartId]
                )
                try dbConn.execute(
                    sql: """
                        INSERT INTO _conflict_log
                        (table_name, record_id, field_name, local_value, remote_value, winner, local_device, remote_device, local_ts, remote_ts, reviewed)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                        """,
                    arguments: ["parts", String(conflictPartId), "company_cost_price", "17.45", "21.90", "remote", "UITEST-LOCAL", "UITEST-REMOTE", now, now]
                )

                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO jobs
                        (job_number, job_name, customer_name, status, priority, job_type,
                         lead_user_id, created_by, notes, created_at, updated_at)
                        VALUES ('UITEST-JPO-001', 'UITesting JPO Smoke Job', 'UITesting Customer',
                                'active', 'normal', 'service', ?, ?,
                                'Deterministic active job for WEI-881 bulk hold smoke', datetime('now'), datetime('now'))
                        """,
                    arguments: [userId, userId]
                )
                try dbConn.execute(
                    sql: """
                        UPDATE jobs
                        SET job_name = 'UITesting JPO Smoke Job', customer_name = 'UITesting Customer',
                            status = 'active', priority = 'normal', job_type = 'service',
                            lead_user_id = ?, created_by = ?, deleted_at = NULL, updated_at = datetime('now')
                        WHERE job_number = 'UITEST-JPO-001'
                        """,
                    arguments: [userId, userId]
                )
                let jobId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM jobs WHERE job_number = 'UITEST-JPO-001' AND deleted_at IS NULL"
                )!

                if ProcessInfo.processInfo.arguments.contains("-UITestingActiveSupplyRunNearMinute") {
                    let now = Date()
                    let clockIn = CoreFormatters.dateTimeSpaceUTC.string(from: now.addingTimeInterval(-300))
                    let supplyRunStart = CoreFormatters.iso8601.string(from: now.addingTimeInterval(-20))
                    try dbConn.execute(
                        sql: "DELETE FROM labor_entries WHERE user_id = ? AND status = 'clocked_in' AND clock_out IS NULL",
                        arguments: [userId]
                    )
                    try dbConn.execute(
                        sql: """
                            INSERT INTO labor_entries
                            (user_id, job_id, clock_in, status, notes, created_at)
                            VALUES (?, ?, ?, 'clocked_in', ?, ?)
                            """,
                        arguments: [userId, jobId, clockIn, "[supply_run_start:\(supplyRunStart)]", clockIn]
                    )
                }

                // The interactive Clock In → Start Supply Run → End Supply Run
                // UI test runs without a simulated GPS fix. Keep the production
                // default (GPS required) intact and make only this deterministic
                // test fixture use the company setting's documented opt-out.
                if ProcessInfo.processInfo.arguments.contains("-UITestingClockInSupplyRunE2E") {
                    try dbConn.execute(
                        sql: """
                            INSERT INTO settings (key, value, category, updated_at)
                            VALUES ('clock_location_required', 'false', 'company', datetime('now'))
                            ON CONFLICT(key) DO UPDATE SET
                                value = 'false', category = 'company', updated_at = datetime('now')
                            """
                    )
                }

                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO job_parts_orders
                        (job_id, order_number, status, priority, order_type, requested_by, notes,
                         created_at, updated_at)
                        VALUES (?, 'UITEST-JPO-001', 'draft', 'normal', 'job', ?,
                                'Deterministic JPO with selectable lines for WEI-881 smoke', datetime('now'), datetime('now'))
                        """,
                    arguments: [jobId, userId]
                )
                try dbConn.execute(
                    sql: """
                        UPDATE job_parts_orders
                        SET job_id = ?, status = 'draft', priority = 'normal', order_type = 'job',
                            requested_by = ?, deleted_at = NULL, updated_at = datetime('now')
                        WHERE order_number = 'UITEST-JPO-001'
                        """,
                    arguments: [jobId, userId]
                )
                let jpoId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM job_parts_orders WHERE order_number = 'UITEST-JPO-001' AND deleted_at IS NULL"
                )!

                for partCode in fixtureParts.map(\.code) {
                    let partId = try Int64.fetchOne(
                        dbConn,
                        sql: "SELECT id FROM parts WHERE code = ? AND deleted_at IS NULL",
                        arguments: [partCode]
                    )!
                    let existingLineCount = try Int.fetchOne(
                        dbConn,
                        sql: """
                            SELECT COUNT(*) FROM jpo_line_items
                            WHERE jpo_id = ? AND part_id = ? AND deleted_at IS NULL
                            """,
                        arguments: [jpoId, partId]
                    ) ?? 0
                    if existingLineCount == 0 {
                        try dbConn.execute(
                            sql: """
                                INSERT INTO jpo_line_items
                                (jpo_id, part_id, qty_requested, qty_ordered, qty_received, priority,
                                 notes, deleted_at, created_at)
                                VALUES (?, ?, 2, 0, 0, 'normal', 'UITesting selectable bulk-hold line', NULL, datetime('now'))
                                """,
                            arguments: [jpoId, partId]
                        )
                    }
                }
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-UITestingWarehouseLocations") {
            try seedWarehouseLocationsUITestingFixtures(db: db)
        }

        let suppressPostLoginOnboarding = ProcessInfo.processInfo.arguments.contains("-UITestingDispatchBoard")
            || ProcessInfo.processInfo.arguments.contains("-UITestingConflictCapture")
            || ProcessInfo.processInfo.arguments.contains("-UITestingWEI3041Timesheets")
            || ProcessInfo.processInfo.arguments.contains("-UITestingTeamsViewOnly")

        if ProcessInfo.processInfo.arguments.contains("-UITestingWEI3041Timesheets") &&
            !ProcessInfo.processInfo.arguments.contains("-UITestingPreserveDatabase") {
            try seedWEI3041TimesheetsFixture(db: db, userId: fixtureUserId)
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            UserDefaults.standard.set(true, forKey: "hasSeenModuleTour")
        }

        if ProcessInfo.processInfo.arguments.contains("-UITestingDispatchBoard") {
            try seedDispatchBoardUITestingFixtures(db: db)
        }

        // QR handoff tests create a real movement draft during their flow. Reset
        // it once at launch so one XCTest case cannot alter another's starting
        // state, while preserving the draft for the in-process scan handoff.
        if ProcessInfo.processInfo.arguments.contains("-UITestingClearMovementWizardDraft") {
            MovementWizardDraftStore.clear(userId: fixtureUserId)
        }

        if suppressPostLoginOnboarding {
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            UserDefaults.standard.set(true, forKey: "hasSeenModuleTour")
        }

        let uiTestingArgs = ProcessInfo.processInfo.arguments
        let shouldRunWEI936NotStartedFixture = uiTestingArgs.contains("-UITestingWEI936NotStarted")
        if shouldRunWEI936NotStartedFixture {
            try clearWEI936OnboardingFixtureSeedDataIfNeeded(db: db)
        }

        if uiTestingArgs.contains("-UITestingWEI3144JobMaterials") {
            try seedWEI3144JobMaterialsFixtures(db: db, userId: fixtureUserId)
        }

        if ProcessInfo.processInfo.arguments.contains("-UITestingStage8Reports") {
            try seedStage8ReportsUITestingFixtures(db: db, userId: fixtureUserId)
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")
        if !suppressPostLoginOnboarding {
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }

        seedWEI936OnboardingStateIfRequested(args: uiTestingArgs, userId: fixtureUserId)

        #if DEBUG && targetEnvironment(simulator)
        if uiTestingArgs.contains(Self.uiTestingLaunchFlag)
            && uiTestingArgs.contains(Self.wei5134AIReadFailureFlag) {
            guard let fixtureUserId else {
                throw UITestBootstrapError.wei5134MissingOwner
            }
            try prepareWEI5134AIReadFailureFixture(db: db, ownerUserId: fixtureUserId)
        } else if uiTestingArgs.contains(Self.uiTestingLaunchFlag)
            && uiTestingArgs.contains(Self.wei5159AIPrerequisiteRecoveryFlag) {
            guard let fixtureUserId else {
                throw UITestBootstrapError.wei5159MissingOwner
            }
            try prepareWEI5159AIPrerequisiteRecoveryFixture(db: db, ownerUserId: fixtureUserId)
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Seeds two owner-scoped transcripts and starts the hermetic UI-test database
    /// with the conversation table unavailable. This method is reachable only from
    /// the doubly flag-gated simulator bootstrap above.
    nonisolated private static func prepareWEI5134AIReadFailureFixture(
        db: AppDatabase,
        ownerUserId: Int64
    ) throws {
        try db.writer.write { dbConn in
            let currentExists = try dbConn.tableExists(Self.wei5134AIConversationTable)
            let backupExists = try dbConn.tableExists(Self.wei5134AIConversationBackupTable)

            switch (currentExists, backupExists) {
            case (true, false):
                try dbConn.execute(
                    sql: "DELETE FROM \(Self.wei5134AIConversationTable) WHERE id LIKE 'wei5134-%'"
                )
                try dbConn.execute(
                    sql: """
                        INSERT INTO \(Self.wei5134AIConversationTable)
                            (id, conversation_id, owner_user_id, role, content, created_at)
                        VALUES
                            ('wei5134-older-message', 'wei5134-older-conversation', ?, 'assistant',
                             'WEI-5134 older saved transcript', '2026-07-17T10:00:00Z'),
                            ('wei5134-latest-message', 'wei5134-latest-conversation', ?, 'assistant',
                             'WEI-5134 latest preserved transcript', '2026-07-17T11:00:00Z')
                        """,
                    arguments: [ownerUserId, ownerUserId]
                )
                try dbConn.execute(
                    sql: "ALTER TABLE \(Self.wei5134AIConversationTable) RENAME TO \(Self.wei5134AIConversationBackupTable)"
                )
            case (false, true):
                break
            case (true, true), (false, false):
                throw UITestBootstrapError.aiConversationFixtureInvalidTableTopology(
                    currentExists: currentExists,
                    backupExists: backupExists
                )
            }
        }
    }

    /// Seeds owner-scoped transcripts while leaving the schema readable. WEI-5159
    /// withholds only the mounted assistant's conversation-read prerequisites.
    nonisolated private static func prepareWEI5159AIPrerequisiteRecoveryFixture(
        db: AppDatabase,
        ownerUserId: Int64
    ) throws {
        try db.writer.write { dbConn in
            let currentExists = try dbConn.tableExists(Self.wei5134AIConversationTable)
            let backupExists = try dbConn.tableExists(Self.wei5134AIConversationBackupTable)
            guard currentExists, !backupExists else {
                throw UITestBootstrapError.aiConversationFixtureInvalidTableTopology(
                    currentExists: currentExists,
                    backupExists: backupExists
                )
            }

            try dbConn.execute(
                sql: "DELETE FROM \(Self.wei5134AIConversationTable) WHERE id LIKE 'wei5134-%'"
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO \(Self.wei5134AIConversationTable)
                        (id, conversation_id, owner_user_id, role, content, created_at)
                    VALUES
                        ('wei5134-older-message', 'wei5134-older-conversation', ?, 'assistant',
                         'WEI-5134 older saved transcript', '2026-07-17T10:00:00Z'),
                        ('wei5134-latest-message', 'wei5134-latest-conversation', ?, 'assistant',
                         'WEI-5134 latest preserved transcript', '2026-07-17T11:00:00Z')
                    """,
                arguments: [ownerUserId, ownerUserId]
            )
        }
    }

    /// Idempotently breaks or restores the AI conversation table through the live
    /// SQLCipher/GRDB connection. No production/device build compiles this surface.
    func setWEI5134AIConversationTableBroken(_ shouldBeBroken: Bool) {
        guard isWEI5134AIReadFailureUITestingMode else { return }
        guard let database = db else {
            wei5134AIReadFailureQAState = "WEI5134 QA table state: error — database unavailable"
            return
        }

        wei5134AIReadFailureQAState = shouldBeBroken
            ? "WEI5134 QA table state: breaking"
            : "WEI5134 QA table state: restoring"

        Task {
            do {
                try await database.writer.write { dbConn in
                    let currentExists = try dbConn.tableExists(Self.wei5134AIConversationTable)
                    let backupExists = try dbConn.tableExists(Self.wei5134AIConversationBackupTable)

                    switch (currentExists, backupExists, shouldBeBroken) {
                    case (true, false, true):
                        try dbConn.execute(
                            sql: "ALTER TABLE \(Self.wei5134AIConversationTable) RENAME TO \(Self.wei5134AIConversationBackupTable)"
                        )
                    case (false, true, false):
                        try dbConn.execute(
                            sql: "ALTER TABLE \(Self.wei5134AIConversationBackupTable) RENAME TO \(Self.wei5134AIConversationTable)"
                        )
                    case (false, true, true), (true, false, false):
                        break
                    case (true, true, _), (false, false, _):
                        throw UITestBootstrapError.aiConversationFixtureInvalidTableTopology(
                            currentExists: currentExists,
                            backupExists: backupExists
                        )
                    }
                }
                wei5134AIReadFailureQAState = shouldBeBroken
                    ? "WEI5134 QA table state: table broken"
                    : "WEI5134 QA table state: table restored"
            } catch {
                logger.error(
                    "WEI-5134 AI conversation table transition failed: \(error.localizedDescription, privacy: .private)"
                )
                wei5134AIReadFailureQAState = "WEI5134 QA table state: error — transition failed"
            }
        }
    }

    /// Withholds or restores only the AI conversation-read prerequisites. The
    /// authenticated shell and dedicated UI-test database remain intact.
    func setWEI5159AIPrerequisitesAvailable(_ available: Bool) {
        guard isWEI5159AIPrerequisiteRecoveryUITestingMode else { return }
        wei5159AIPrerequisitesAvailable = available
        if !available {
            wei5159AIConversationListSuspended = false
        }
        wei5159AIPrerequisiteQAState = available
            ? "WEI5159 QA prerequisites: available"
            : "WEI5159 QA prerequisites: unavailable"
    }

    /// Simulator-only gate that makes an in-flight Resume request observable
    /// before the WEI-5159 control withdraws its read prerequisites.
    func setWEI5159AIConversationListSuspended(_ suspended: Bool) {
        guard isWEI5159AIPrerequisiteRecoveryUITestingMode else { return }
        wei5159AIConversationListSuspended = suspended
    }

    func waitForWEI5159AIConversationListLoadReleaseIfNeeded() async {
        guard isWEI5159AIPrerequisiteRecoveryUITestingMode else { return }
        while wei5159AIConversationListSuspended,
              wei5159AIPrerequisitesAvailable,
              !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    #endif

    nonisolated static func uiTestingWEI3144JobMaterialsJobId(db: AppDatabase?) -> Int64? {
        guard ProcessInfo.processInfo.arguments.contains("-UITestingWEI3144JobMaterials"),
              let db
        else { return nil }
        return uiTestingJobId(db: db, jobNumber: "UITEST-MAT-3144")
    }

    nonisolated static func uiTestingJobId(db: AppDatabase?, jobNumber: String) -> Int64? {
        guard let db else { return nil }
        return try? db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM jobs WHERE job_number = ? AND deleted_at IS NULL",
                arguments: [jobNumber]
            )
        }
    }

    nonisolated static func stage8ReportsUITestAuditSessionId(db: AppDatabase?) -> Int64? {
        guard ProcessInfo.processInfo.arguments.contains("-UITestingStage8Reports"),
              let db
        else { return nil }

        return try? db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: """
                    SELECT id
                    FROM audit_sessions_v2
                    WHERE notes = 'WEI-3295 Stage 8 reports viewport seed'
                      AND deleted_at IS NULL
                    ORDER BY id DESC
                    LIMIT 1
                    """
            )
        }
    }

    nonisolated private static func seedStage8ReportsUITestingFixtures(db: AppDatabase, userId: Int64?) throws {
        guard let userId else { return }

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO suppliers
                    (name, contact_name, email, is_active, deleted_at, created_at, updated_at)
                    VALUES ('WEI-3295 Electrical Supply', 'Stage 8 QA', 'stage8@example.test', 1, NULL, datetime('now'), datetime('now'))
                    """
            )
            let supplierId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM suppliers WHERE name = 'WEI-3295 Electrical Supply' AND deleted_at IS NULL"
            )!

            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO part_categories
                    (name, description, sort_order, is_active, deleted_at, created_at, updated_at)
                    VALUES ('WEI-3295 Stage 8 Reports', 'Deterministic report viewport fixture category', 0, 1, NULL, datetime('now'), datetime('now'))
                    """
            )
            let categoryId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM part_categories WHERE name = 'WEI-3295 Stage 8 Reports' AND deleted_at IS NULL"
            )!

            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO parts
                    (category_id, part_type, code, name, description, unit_of_measure,
                     company_cost_price, company_markup_percent, is_active, deleted_at, created_at, updated_at)
                    VALUES (?, 'general', 'WEI3295-STAGE8', 'WEI-3295 Stage 8 Breaker',
                            'Seeded part for Stage 8 reports viewport harness', 'each',
                            42.50, 25.0, 1, NULL, datetime('now'), datetime('now'))
                    """,
                arguments: [categoryId]
            )
            let partId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM parts WHERE code = 'WEI3295-STAGE8' AND deleted_at IS NULL"
            )!

            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO jobs
                    (job_number, job_name, customer_name, status, priority, job_type,
                     billing_rate, lead_user_id, created_by, notes, deleted_at, created_at, updated_at)
                    VALUES ('UITEST-STAGE8-3295', 'WEI-3295 Stage 8 Billing QA Job',
                            'Stage 8 Fixture Customer', 'active', 'high', 'service',
                            125.0, ?, ?, 'Seeded for Stage 8 reports viewport verification.', NULL, datetime('now'), datetime('now'))
                    """,
                arguments: [userId, userId]
            )
            let jobId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM jobs WHERE job_number = 'UITEST-STAGE8-3295' AND deleted_at IS NULL"
            )!

            try dbConn.execute(
                sql: """
                    DELETE FROM labor_entries
                    WHERE notes = 'WEI-3295 Stage 8 reports viewport seed'
                    """
            )
            // Seed inside the CURRENT local day, never "yesterday": report
            // pages default to the "This Period" range (pay-period start ..
            // now), and a pay-period boundary falling on today puts any
            // yesterday-dated seed into the PREVIOUS period — every gate run
            // then fails with "No labor entries found for the selected
            // period" until the next boundary (observed fleet-wide on
            // 2026-07-30). Start-of-local-day is always >= the period start
            // and <= now, so it is in-range on every calendar date.
            try dbConn.execute(
                sql: """
                    INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours,
                     status, notes, deleted_at, created_at)
                    VALUES (?, ?, datetime('now', 'localtime', 'start of day', 'utc'),
                            datetime('now'),
                            8.0, 1.0, 'completed', 'WEI-3295 Stage 8 reports viewport seed', NULL,
                            datetime('now', 'localtime', 'start of day', 'utc'))
                    """,
                arguments: [userId, jobId]
            )

            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO purchase_orders
                    (po_number, supplier_id, status, order_date, subtotal, tax_amount, shipping_cost,
                     total_cost, notes, submitted_by, deleted_at, created_at, updated_at)
                    VALUES ('PO-WEI3295-STAGE8', ?, 'ordered', date('now', 'localtime'), 127.50, 0, 0,
                            127.50, 'WEI-3295 Stage 8 reports viewport seed', ?, NULL,
                            datetime('now', 'localtime', 'start of day', 'utc'), datetime('now'))
                    """,
                arguments: [supplierId, userId]
            )
            let poId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI3295-STAGE8' AND deleted_at IS NULL"
            )!
            try dbConn.execute(
                sql: "DELETE FROM po_line_items WHERE po_id = ?",
                arguments: [poId]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO po_line_items
                    (po_id, part_id, qty_ordered, qty_received, unit_cost, status, notes, deleted_at, created_at)
                    VALUES (?, ?, 3, 0, 42.50, 'pending', 'WEI-3295 Stage 8 reports viewport seed', NULL, datetime('now'))
                    """,
                arguments: [poId, partId]
            )

            try dbConn.execute(
                sql: """
                    DELETE FROM stock
                    WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1
                    """,
                arguments: [partId]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO stock
                    (part_id, location_type, location_id, qty, supplier_id, last_counted, counted_qty, deleted_at, updated_at)
                    VALUES (?, 'warehouse', 1, 12, ?, datetime('now'), 9, NULL, datetime('now'))
                    """,
                arguments: [partId, supplierId]
            )

            var auditAreaId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM warehouse_storage_areas WHERE full_location_code = 'WEI-3295-A1' AND deleted_at IS NULL LIMIT 1"
            )
            if auditAreaId == nil {
                try dbConn.execute(
                    sql: """
                        INSERT INTO warehouse_floor_plans
                        (name, width_inches, length_inches, is_active, created_at, updated_at, deleted_at)
                        VALUES ('WEI-3295 Stage 8 QA Floor', 120, 120, 1, datetime('now'), datetime('now'), NULL)
                        """
                )
                let floorPlanId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM warehouse_floor_plans WHERE name = 'WEI-3295 Stage 8 QA Floor' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1"
                )!
                try dbConn.execute(
                    sql: """
                        INSERT INTO warehouse_storage_units
                        (floor_plan_id, name, unit_type, unit_number, is_configured, created_at, updated_at, deleted_at)
                        VALUES (?, 'WEI-3295 QA Shelf', 'shelf', 'WEI3295', 1, datetime('now'), datetime('now'), NULL)
                        """,
                    arguments: [floorPlanId]
                )
                let unitId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM warehouse_storage_units WHERE name = 'WEI-3295 QA Shelf' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1"
                )!
                try dbConn.execute(
                    sql: """
                        INSERT INTO warehouse_storage_levels
                        (unit_id, level_code, level_name, level_order, area_count, created_at, deleted_at)
                        VALUES (?, 'A', 'QA Shelf Level A', 1, 1, datetime('now'), NULL)
                        """,
                    arguments: [unitId]
                )
                let levelId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM warehouse_storage_levels WHERE unit_id = ? AND level_code = 'A' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1",
                    arguments: [unitId]
                )!
                try dbConn.execute(
                    sql: """
                        INSERT INTO warehouse_storage_areas
                        (level_id, area_code, area_number, width_inches, has_qr_code, has_sticker, full_location_code, created_at, deleted_at)
                        VALUES (?, 'A1', 1, 24, 0, 0, 'WEI-3295-A1', datetime('now'), NULL)
                        """,
                    arguments: [levelId]
                )
                auditAreaId = try Int64.fetchOne(
                    dbConn,
                    sql: "SELECT id FROM warehouse_storage_areas WHERE full_location_code = 'WEI-3295-A1' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1"
                )
            }

            try dbConn.execute(
                sql: """
                    DELETE FROM audit_sessions_v2
                    WHERE notes = 'WEI-3295 Stage 8 reports viewport seed'
                    """,
            )

            try dbConn.execute(
                sql: """
                    INSERT INTO audit_sessions_v2
                    (session_type, started_by, status, parts_counted, discrepancies_found, notes, started_at, deleted_at)
                    VALUES ('count', ?, 'active', 1, 1, 'WEI-3295 Stage 8 reports viewport seed', datetime('now'), NULL)
                    """,
                arguments: [userId]
            )
            let auditSessionId = try Int64.fetchOne(
                dbConn,
                sql: """
                    SELECT id
                    FROM audit_sessions_v2
                    WHERE notes = 'WEI-3295 Stage 8 reports viewport seed'
                      AND deleted_at IS NULL
                    ORDER BY id DESC
                    LIMIT 1
                    """
            )!
            try dbConn.execute(
                sql: """
                    INSERT INTO audit_counts
                    (session_id, part_id, area_id, system_count, user_count, variance,
                     variance_dollars, variance_percent, result, counted_by, counted_at)
                    VALUES (?, ?, ?, 12, 9, -3, 127.50, -25.0, 'variance', ?, datetime('now'))
                    """,
                arguments: [auditSessionId, partId, auditAreaId!, userId]
            )
        }
    }

    nonisolated private static func seedWEI3144JobMaterialsFixtures(db: AppDatabase, userId: Int64?) throws {
        guard let userId else { return }

        // Guard against duplicate seeding when the app is relaunched with the same
        // persisted DB (e.g. repeated Simulator runs with -UITestingWEI3144JobMaterials).
        let alreadySeeded = (try? db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM jobs WHERE job_number = 'UITEST-MAT-3144' AND deleted_at IS NULL"
            )
        }) != nil
        if alreadySeeded { return }

        let parts = PartsService(db: db, auth: AuthService(db: db))
        let warehouse = WarehouseService(db: db)
        let jobs = JobsService(db: db)
        let categoryId = try parts.createCategory(name: "UITesting WEI-3144 Electrical", description: "Seeded material QA category")

        let wireNutId = try parts.createPart(
            categoryId: categoryId,
            name: "WEI-3144 Wire Nut",
            code: "WEI3144-WIRE-NUT",
            description: "Seeded wire nut for pull, consume, and return mobile QA"
        )
        let correctionPartId = try parts.createPart(
            categoryId: categoryId,
            name: "WEI-3144 Correction Wire Nut",
            code: "WEI3144-CORRECT",
            description: "Seeded material correction row for audit-note QA"
        )
        let jobId = try jobs.createJob(
            jobNumber: "UITEST-MAT-3144",
            jobName: "WEI-3144 Materials QA Job",
            customerName: "Seeded QA Customer",
            status: "active",
            priority: "high",
            jobType: "service",
            notes: "Seeded for Stage 6 parts-on-jobs mobile/tablet Materials QA.",
            createdBy: userId
        )

        _ = try warehouse.createMovement(
            partId: wireNutId,
            qty: 10,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: StockMovement.MovementType.receive.rawValue,
            reason: "WEI-3144 seed stock",
            performedBy: userId
        )
        _ = try jobs.pullJobMaterial(
            jobId: jobId,
            partId: wireNutId,
            qty: 10,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            performedBy: userId,
            notes: "Pulled 10 wire nuts for seeded Materials QA"
        )
        _ = try jobs.consumeStagedJobMaterial(
            jobId: jobId,
            partId: wireNutId,
            qty: 7,
            performedBy: userId,
            notes: "Consumed 7 wire nuts in seeded Materials QA"
        )
        _ = try jobs.returnPulledJobMaterial(
            jobId: jobId,
            partId: wireNutId,
            qty: 3,
            toLocationType: "warehouse",
            toLocationId: 1,
            performedBy: userId,
            notes: "Returned 3 unused wire nuts in seeded Materials QA"
        )

        let correctionJobPartId = try jobs.addJobPart(
            jobId: jobId,
            partId: correctionPartId,
            qty: 9,
            costAtConsume: 1.25,
            performedBy: userId
        )
        try jobs.correctConsumedJobMaterial(
            jobPartId: correctionJobPartId,
            adjustedQty: 7,
            performedBy: userId,
            note: "Seeded correction validates required audit note."
        )
    }

    nonisolated private static func seedWEI3041TimesheetsFixture(db: AppDatabase, userId: Int64?) throws {
        guard let userId else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dayStart = calendar.startOfDay(for: Date())
        let firstClockIn = CoreFormatters.iso8601.string(from: calendar.date(byAdding: .hour, value: 8, to: dayStart) ?? dayStart)
        let firstClockOut = CoreFormatters.iso8601.string(from: calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart)
        let secondClockIn = CoreFormatters.iso8601.string(from: calendar.date(byAdding: .minute, value: 750, to: dayStart) ?? dayStart)
        let secondClockOut = CoreFormatters.iso8601.string(from: calendar.date(byAdding: .minute, value: 990, to: dayStart) ?? dayStart)

        try db.writer.write { dbConn in
            let existingOvertimeSettingsId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM overtime_settings ORDER BY id LIMIT 1"
            )
            if let existingOvertimeSettingsId {
                try dbConn.execute(sql: """
                    UPDATE overtime_settings
                    SET calculation_rule = 'weekly_only',
                        daily_threshold_hours = 8.0,
                        weekly_threshold_hours = 6.0,
                        week_start_weekday = 2,
                        updated_by = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [userId, existingOvertimeSettingsId])
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO overtime_settings
                        (calculation_rule, daily_threshold_hours, weekly_threshold_hours,
                         week_start_weekday, updated_by, updated_at)
                    VALUES ('weekly_only', 8.0, 6.0, 2, ?, datetime('now'))
                    """, arguments: [userId])
            }

            try dbConn.execute(sql: """
                INSERT OR IGNORE INTO jobs
                    (job_number, job_name, customer_name, status, priority, job_type,
                     lead_user_id, created_by, notes, created_at, updated_at)
                VALUES ('UITEST-WEI-3041', 'WEI-3041 Correction Overtime Job', 'UITesting Customer',
                        'active', 'normal', 'service', ?, ?,
                        'Deterministic timesheet correction fixture for non-default overtime QA',
                        datetime('now'), datetime('now'))
                """, arguments: [userId, userId])
            try dbConn.execute(sql: """
                UPDATE jobs
                SET job_name = 'WEI-3041 Correction Overtime Job',
                    customer_name = 'UITesting Customer',
                    status = 'active',
                    priority = 'normal',
                    job_type = 'service',
                    lead_user_id = ?,
                    created_by = ?,
                    deleted_at = NULL,
                    updated_at = datetime('now')
                WHERE job_number = 'UITEST-WEI-3041'
                """, arguments: [userId, userId])
            let jobId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM jobs WHERE job_number = 'UITEST-WEI-3041' AND deleted_at IS NULL LIMIT 1"
            )!

            try dbConn.execute(sql: """
                DELETE FROM timesheet_correction_audits
                WHERE labor_entry_id IN (
                    SELECT id FROM labor_entries
                    WHERE job_id = ? AND user_id = ?
                )
                """, arguments: [jobId, userId])
            try dbConn.execute(sql: """
                DELETE FROM labor_entries
                WHERE job_id = ? AND user_id = ?
                """, arguments: [jobId, userId])

            try dbConn.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES
                    (?, ?, ?, ?, 4.0, 0.0, 'completed', datetime('now')),
                    (?, ?, ?, ?, 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [
                userId, jobId, firstClockIn, firstClockOut,
                userId, jobId, secondClockIn, secondClockOut
            ])
        }
    }

    nonisolated private static func seedWarehouseLocationsUITestingFixtures(db: AppDatabase) throws {
        let service = WarehouseService(db: db)
        let planName = "UITesting Warehouse Floor Plan"
        let plan = try service.listFloorPlans().first { $0.name == planName }
            ?? (try service.createFloorPlan(name: planName, widthInches: 720, lengthInches: 480))

        guard let planId = plan.id else { return }
        try service.updateFloorPlanGrid(floorPlanId: planId, rows: 3, cols: 5)

        if try service.listZones(floorPlanId: planId).isEmpty {
            _ = try service.addZone(
                floorPlanId: planId,
                zoneType: "storage",
                label: "UITesting Storage",
                colorHex: "#2563EB",
                gridX: 0,
                gridY: 0,
                gridWidth: 2,
                gridHeight: 2
            )
        }

        let existingUnits = try service.listStorageUnits(floorPlanId: planId)
        if existingUnits.isEmpty {
            let shelf = try service.createStorageUnit(
                floorPlanId: planId,
                name: "UITesting Shelf A",
                unitType: "shelf",
                levels: 2,
                areasPerLevel: 3
            )
            if let shelfId = shelf.id {
                try service.updateStorageUnit(
                    id: shelfId,
                    gridX: 0,
                    gridY: 0,
                    gridWidth: 1,
                    gridHeight: 2,
                    frontFace: "south"
                )
            }

            let rack = try service.createStorageUnit(
                floorPlanId: planId,
                name: "UITesting Pipe Rack",
                unitType: "rack",
                levels: 1,
                areasPerLevel: 4
            )
            if let rackId = rack.id {
                try service.updateStorageUnit(
                    id: rackId,
                    gridX: 2,
                    gridY: 1,
                    gridWidth: 2,
                    gridHeight: 1,
                    frontFace: "east"
                )
            }
        }
    }

    nonisolated private static func clearWEI936OnboardingFixtureSeedDataIfNeeded(db: AppDatabase) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM job_parts_orders WHERE order_number = 'UITEST-JPO-001'")
            try dbConn.execute(sql: "DELETE FROM jobs WHERE job_number = 'UITEST-JPO-001'")
            try dbConn.execute(sql: "DELETE FROM parts WHERE code IN ('UITEST-QA-CONDUIT', 'UITEST-QA-WIRE')")
            try dbConn.execute(sql: "DELETE FROM part_categories WHERE name = 'UITesting Electrical'")
            try dbConn.execute(sql: "DELETE FROM _conflict_log WHERE table_name IN ('parts','jobs') AND record_id IN ('1001', '1002', '2001')")
        }
    }

    nonisolated private static func seedWEI936OnboardingStateIfRequested(args: [String], userId: Int64?) {
        guard args.contains("-UITestingWEI936TourActive") ||
            args.contains("-UITestingWEI936RequiredDone") ||
            args.contains("-UITestingWEI1451DashboardCard") ||
            args.contains("-UITestingWEI1451DismissedToast") ||
            args.contains("-UITestingWEI936DismissedChecklist") ||
            args.contains("-UITestingWEI936NotStarted") ||
            args.contains("-UITestingWEI936Celebration") else { return }

        UserDefaults.standard.removeObject(forKey: "onboarding_checklist_dismissed")
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        if args.contains("-UITestingWEI936NotStarted") {
            UserDefaults.standard.set(true, forKey: "hasSeenModuleTour")
        }

        if let userId {
            let storageKey = "onboarding_progress_\(userId)"
            let shouldActivateTour = !args.contains("-UITestingWEI936NotStarted")
            UserDefaults.standard.set(shouldActivateTour, forKey: storageKey + "_active")

            var completedTasks: Set<String> = []
            // UITestingWEI936NotStarted: ensure the Getting Started checklist is
            // visible and the app tour is inactive. No per-page guidance banner,
            // no pre-completed tasks.
            // UITestingWEI936TourActive: begin with an empty task set so the
            // "Try This" guidance banner renders on pages with incomplete required
            // tasks. The dashboard auto-marks dashboard-view-kpis via its .task
            // modifier; the dedicated WEI936 QA harness navigates to the Jobs page,
            // where jobs-create and jobs-tap-detail remain incomplete for a stable
            // capture even after jobs-view-list is auto-marked.
            if args.contains("-UITestingWEI936RequiredDone") {
                completedTasks.formUnion(["dashboard-view-kpis", "dashboard-tap-kpi"])
            }
            if shouldActivateTour, let data = try? JSONEncoder().encode(completedTasks) {
                UserDefaults.standard.set(data, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        if args.contains("-UITestingWEI936DismissedChecklist") ||
            args.contains("-UITestingWEI1451DismissedToast") {
            UserDefaults.standard.set(true, forKey: "onboarding_checklist_dismissed")
        }
    }

    nonisolated private static func seedDispatchBoardUITestingFixtures(db: AppDatabase) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today
        let sourceDate = formatter.string(from: weekStart)
        let targetDate = formatter.string(from: calendar.date(byAdding: .day, value: 1, to: weekStart) ?? today)
        let conflictDate = formatter.string(from: calendar.date(byAdding: .day, value: 2, to: weekStart) ?? today)

        try db.writer.write { dbConn in
            let ownerId = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM users WHERE display_name = ? AND deleted_at IS NULL LIMIT 1",
                arguments: ["UITest Owner"]
            ) ?? 1

            try dbConn.execute(
                sql: """
                    INSERT INTO users (display_name, pin_hash, pin_salt, is_active, created_at, updated_at)
                    SELECT ?, ?, ?, 1, datetime('now'), datetime('now')
                    WHERE NOT EXISTS (
                        SELECT 1 FROM users WHERE display_name = ? AND deleted_at IS NULL
                    )
                    """,
                arguments: ["UITest Spare Worker", "uitest-hash", "uitest-salt", "UITest Spare Worker"]
            )

            try dbConn.execute(
                sql: """
                    INSERT INTO jobs (job_number, job_name, status, priority, job_type, created_by, created_at, updated_at)
                    VALUES (?, ?, 'active', 'normal', 'service', ?, datetime('now'), datetime('now'))
                    ON CONFLICT(job_number) DO UPDATE SET
                        job_name = excluded.job_name,
                        status = 'active',
                        deleted_at = NULL,
                        updated_at = datetime('now')
                    """,
                arguments: ["UITEST-DISPATCH-A", "UITest Source Dispatch Job", ownerId]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO jobs (job_number, job_name, status, priority, job_type, created_by, created_at, updated_at)
                    VALUES (?, ?, 'active', 'normal', 'service', ?, datetime('now'), datetime('now'))
                    ON CONFLICT(job_number) DO UPDATE SET
                        job_name = excluded.job_name,
                        status = 'active',
                        deleted_at = NULL,
                        updated_at = datetime('now')
                    """,
                arguments: ["UITEST-DISPATCH-B", "UITest Target Dispatch Job", ownerId]
            )

            let sourceJobId = try Int64.fetchOne(dbConn, sql: "SELECT id FROM jobs WHERE job_number = ?", arguments: ["UITEST-DISPATCH-A"]) ?? 0
            let targetJobId = try Int64.fetchOne(dbConn, sql: "SELECT id FROM jobs WHERE job_number = ?", arguments: ["UITEST-DISPATCH-B"]) ?? 0

            try dbConn.execute(
                sql: "DELETE FROM job_dispatch WHERE job_id IN (?, ?) OR user_id = ?",
                arguments: [sourceJobId, targetJobId, ownerId]
            )
            try dbConn.execute(
                sql: "DELETE FROM schedule_exceptions WHERE user_id = ?",
                arguments: [ownerId]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO job_dispatch
                    (job_id, user_id, dispatch_date, role_on_job, status, dispatched_by, time_slot, created_at, updated_at)
                    VALUES (?, ?, ?, 'worker', 'scheduled', ?, 'am', datetime('now'), datetime('now'))
                    """,
                arguments: [sourceJobId, ownerId, sourceDate, ownerId]
            )
            try dbConn.execute(
                sql: """
                    INSERT INTO schedule_exceptions
                    (user_id, exception_date, exception_type, reason, is_approved, created_at)
                    VALUES (?, ?, 'time_off', 'UITest approved PTO', 1, datetime('now'))
                    """,
                arguments: [ownerId, conflictDate]
            )
        }
        UserDefaults.standard.set(targetDate, forKey: "uiTestingDispatchTargetDate")
    }
}
