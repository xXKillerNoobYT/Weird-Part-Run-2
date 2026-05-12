import SwiftUI
import Combine
import WiredPartCore
import GRDB
import os.log

/// Shared application state that owns the database and all services.
///
/// Published as an `@EnvironmentObject` so every view in the tree
/// can access services and the current user without prop-drilling.
@MainActor
final class AppCore: ObservableObject {
    private static let uiTestingLaunchFlag = "-UITesting"

    // MARK: - Published State

    @Published var isReady = false
    @Published var loadError: String?
    @Published var needsBootstrap = false
    @Published var needsOnboarding = false
    @Published var currentUser: User?
    @Published var currentToken: String?
    @Published var permissions: [String] = []
    @Published var theme: SettingsService.ThemeSettings = .defaults

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

    private func bootstrap() async {
        do {
            let uiTestingMode = isUITestingMode
            // Resolve the database path on the main actor (it accesses FileManager),
            // then perform all blocking database work off the main thread to avoid
            // priority inversion (user-interactive main thread waiting on
            // GRDB's default-QoS pool semaphore).
            let path = try Self.databasePath(isUITesting: uiTestingMode)
            if uiTestingMode {
                try Self.resetUITestDatabase(atPath: path)
            }

            // NOTE: resetDatabaseIfNewBuild() was removed (GitHub #101).
            // It compared the binary's mod date and wiped the DB on every
            // Cmd+R rebuild. Clean builds already delete the simulator
            // sandbox, so migrations create tables from scratch naturally.
            let result = try await Task.detached(priority: .userInitiated) {
                // Production safety: back up before migration so we can roll back
                #if !DEBUG
                let backupPath = AppDatabase.backupDatabase(atPath: path)
                #endif

                let database: AppDatabase
                do {
                    database = try AppDatabase.openDatabase(atPath: path)
                } catch {
                    #if !DEBUG
                    // Migration failed — try to restore from backup
                    if let backup = backupPath {
                        try? AppDatabase.restoreDatabase(from: backup, to: path)
                        // Retry with restored DB (old schema, but data preserved)
                        logger.error("[AppCore] Migration failed, restored from backup. Error: \(error.localizedDescription)")
                    }
                    #endif
                    throw error
                }

                let auth = AuthService(db: database)
                let settings = SettingsService(db: database)
                if uiTestingMode {
                    try Self.seedUITestingFixtures(db: database, authService: auth)
                }

                let theme = try? settings.getTheme()
                let users = try auth.getActiveUsers()
                let hasProfile = try settings.hasBusinessProfile()

                // Compute UITesting permissions here (off main thread) to avoid
                // priority inversion from synchronous DB reads on @MainActor.
                var uiTestingPermissions: [String] = []
                if uiTestingMode, let user = users.first, let userId = user.id {
                    uiTestingPermissions = (try? auth.getUserPermissions(userId)) ?? []
                }

                return (
                    database: database,
                    auth: auth,
                    settings: settings,
                    parts: PartsService(db: database),
                    warehouse: WarehouseService(db: database),
                    jobs: JobsService(db: database),
                    orders: OrdersService(db: database),
                    fleet: FleetService(db: database),
                    people: PeopleService(db: database),
                    scheduling: SchedulingService(db: database),
                    chat: ChatService(db: database),
                    notebooks: NotebooksService(db: database),
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
                    hasProfile: hasProfile,
                    uiTestingPermissions: uiTestingPermissions
                )
            }.value

            // Apply results back on MainActor
            db = result.database
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

            if uiTestingMode, let user = result.users.first, let userId = user.id {
                currentUser = user
                permissions = result.uiTestingPermissions
                currentToken = "ui-testing"
                onboardingManager = OnboardingProgressManager(userId: userId)
                badgeCountManager.setUserId(userId)
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
                if syncManager.isSyncAvailable {
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
            runScheduledMaintenanceIfNeeded()

            // Run companion auto-discovery cycle in the background (logged)
            Task.detached { [partsService, backgroundTaskService] in
                let taskId = try? backgroundTaskService?.startTask(
                    name: "Companion Auto-Discovery",
                    type: "companion_discovery"
                )
                do {
                    try partsService?.runAutoDiscoveryCycle()
                    if let taskId {
                        try? backgroundTaskService?.completeTask(
                            id: taskId,
                            summary: "Discovery cycle completed"
                        )
                    }
                } catch {
                    if let taskId {
                        try? backgroundTaskService?.failTask(
                            id: taskId,
                            error: error.localizedDescription
                        )
                    }
                }
            }

            // Ensure Office chat channel exists (auto-created system channel)
            Task.detached { [chatService, backgroundTaskService] in
                let taskId = try? backgroundTaskService?.startTask(
                    name: "Office Channel Setup",
                    type: "system_setup"
                )
                do {
                    try chatService?.ensureOfficeChannel()
                    if let taskId {
                        try? backgroundTaskService?.completeTask(
                            id: taskId,
                            summary: "Office channel ready"
                        )
                    }
                } catch {
                    if let taskId {
                        try? backgroundTaskService?.failTask(
                            id: taskId,
                            error: error.localizedDescription
                        )
                    }
                }
            }
        } catch {
            loadError = userFriendlyError(error, context: "start app")
        }
    }

    /// Retry bootstrap after a failure.
    func retryBootstrap() {
        loadError = nil
        Task { @MainActor in
            await bootstrap()
        }
    }

    func runScheduledMaintenanceIfNeeded() {
        guard let backgroundTaskService, let toolsService else { return }
        let logger = self.logger
        Task.detached { [backgroundTaskService, toolsService] in
            do {
                _ = try backgroundTaskService.runToolsMaintenance(toolsService: toolsService)
            } catch {
                logger.error("[AppCore] Tools maintenance failed: \(error.localizedDescription)")
            }
        }
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

    /// Reload theme settings from the database and apply them.
    func updateTheme() {
        guard let settings = settingsService else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let theme = (try? settings.getTheme()) ?? .defaults
            await MainActor.run {
                self?.theme = theme
            }
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

        // 3. Delete the database file
        try DeviceResetService.deleteDatabaseFile(atPath: dbPath)

        // 4. Clear saved session and all onboarding UserDefaults flags so the
        //    fresh DB is not skipped by stale "already completed" flags.
        currentUser = nil
        currentToken = nil
        permissions = []
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "hasCompletedCompanySetup")
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")

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

    // MARK: - Database Path

    enum AppCoreError: LocalizedError {
        case noDocumentsDirectory
        var errorDescription: String? {
            "Unable to locate app storage directory. Please restart the app."
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

    nonisolated private static func seedUITestingFixtures(db: AppDatabase, authService: AuthService) throws {
        _ = try authService.seedFirstAdmin(displayName: "UITest Owner", pin: "1234")

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
            try dbConn.execute(
                sql: """
                    INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value, winner, local_device, remote_device, local_ts, remote_ts, reviewed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: ["parts", "2001", "unit_cost", "17.45", "21.90", "remote", "UITEST-LOCAL", "UITEST-REMOTE", now, now]
            )
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        UserDefaults.standard.set(true, forKey: "hasSeenOnboardAIMVPEntry")
        UserDefaults.standard.set(true, forKey: "hasSeenModuleTour")
    }
}
