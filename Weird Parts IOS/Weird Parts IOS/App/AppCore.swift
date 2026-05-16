import SwiftUI
import Combine
import WiredPartCore
import Security
import GRDB
import os.log

/// Shared application state that owns the database and all services.
///
/// Published as an `@EnvironmentObject` so every view in the tree
/// can access services and the current user without prop-drilling.
@MainActor
final class AppCore: ObservableObject {
    private static let uiTestingLaunchFlag = "-UITesting"
    private static let uiTestingPreserveDatabaseFlag = "-UITestingPreserveDatabase"
    private static let uiTestingMultiUserVerificationFixtureFlag = "-UITestingMultiUserVerificationFixture"

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

    private var shouldPreserveUITestDatabase: Bool {
        ProcessInfo.processInfo.arguments.contains(Self.uiTestingPreserveDatabaseFlag)
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
// SQLCipher: derive a device-bound bootstrap key from the Keychain.
                    // This key never changes unless the Keychain is wiped (device reset).
                    // User PIN changes update authentication credentials only; the app DB
                    // stays on this device key so startup can always open it before login.
                    //
                    // Migration path: if the DB file is still plaintext (pre-SQLCipher binary),
                    // `migratePlaintextDBIfNeeded` converts it in-place before opening.
                    let keyHex: String
                    #if DEBUG
                    if uiTestingMode {
                        keyHex = Self.uiTestingBootstrapKeyHex
                    } else {
                        keyHex = try Self.deviceBootstrapKeyHex()
                    }
                    #else
                    keyHex = try Self.deviceBootstrapKeyHex()
                    #endif
                    try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)
                    database = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
                    // Remove the .unencrypted.bak file after it has been retained for 7 days.
                    AppDatabase.cleanupStaleUnencryptedBackup(atPath: path)
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
                    hasProfile: hasProfile
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
            #if DEBUG
            if isUITestingMode {
                loadError = "Couldn't start app. \(error.localizedDescription)"
            } else {
                loadError = userFriendlyError(error, context: "start app")
            }
            #else
            loadError = userFriendlyError(error, context: "start app")
            #endif
        }
    }

    /// Retry bootstrap after a failure.
    func retryBootstrap() {
        loadError = nil
        Task { @MainActor in
            await bootstrap()
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

    // MARK: - SQLCipher Device Bootstrap Key

    /// Test-only SQLCipher key for the resettable `wiredpart-uitesting.sqlite` database.
    ///
    /// UI tests run under simulator/XCTest launch contexts where Keychain access can
    /// fail with errSecMissingEntitlement (-34018). Production and normal debug app
    /// launches still use the device-bound Keychain key below.
    nonisolated private static let uiTestingBootstrapKeyHex =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    /// Return the device-bound SQLCipher bootstrap key (hex-encoded 64 chars).
    ///
    /// This key is used exclusively to encrypt the database file. It is a random
    /// 32-byte value generated on first launch and stored in the Keychain with
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It never changes.
    ///
    /// User PIN changes do not re-key the app database. Startup must open the DB
    /// before any user can enter a PIN, so the persistent DB key remains device-bound.
    nonisolated static func deviceBootstrapKeyHex() throws -> String {
        let uiTestingLaunchFlag = "-UITesting"
        let uiTestingDatabaseKeyHex = "8f1df32f4be04d5fcde1e8e6ddf9187f53a4b68370d5aafc56f0d43f2e9732a1"
        if ProcessInfo.processInfo.arguments.contains(uiTestingLaunchFlag) {
            return uiTestingDatabaseKeyHex
        }

        let service = "com.wiredpart.dbcipher.bootstrap-key"
        let account = "device-bootstrap-key"

        // Try to read existing key.
        let readQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if readStatus == errSecSuccess, let data = result as? Data, data.count == 32 {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        if readStatus == errSecSuccess {
            // Self-heal legacy/corrupt keychain entries so startup can recover.
            let deleteQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
        }

        // Generate 32 fresh random bytes.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard rc == errSecSuccess else {
            throw CipherKeyError.bootstrapKeyGenerationFailed(rc)
        }
        let keyData = Data(keyBytes)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another thread or launch already stored a bootstrap key — read and return it
            // so we don't encrypt the DB with a key that won't be retrievable next launch.
            var existing: AnyObject?
            let rereadStatus = SecItemCopyMatching(readQuery as CFDictionary, &existing)
            if rereadStatus == errSecSuccess, let data = existing as? Data, data.count == 32 {
                return data.map { String(format: "%02x", $0) }.joined()
            }
            let deleteQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
            let retryAddStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if retryAddStatus == errSecSuccess {
                return keyData.map { String(format: "%02x", $0) }.joined()
            }
            throw CipherKeyError.keychainAccessFailed(retryAddStatus)
        } else if addStatus != errSecSuccess {
            throw CipherKeyError.keychainAccessFailed(addStatus)
        }
        return keyData.map { String(format: "%02x", $0) }.joined()
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
            try await Task.detached(priority: .userInitiated) {
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
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")

        try seedMultiUserVerificationFixturesIfRequested(db: db, authService: authService)
    }

    nonisolated private static func seedMultiUserVerificationFixturesIfRequested(
        db: AppDatabase,
        authService: AuthService
    ) throws {
        guard ProcessInfo.processInfo.arguments.contains("-UITestingMultiUserVerificationFixture") else { return }

        let partsService = PartsService(db: db, auth: authService)
        let warehouseService = WarehouseService(db: db)
        let now = ISO8601DateFormatter().string(from: Date())

        let usersByName: [String: Int64] = try Dictionary(
            uniqueKeysWithValues: authService.getActiveUsers().compactMap { user in
                guard let id = user.id else { return nil }
                return (user.displayName, id)
            }
        )
        let ownerId = usersByName["UITest Owner"] ?? 1
        // Use distinct PINs for non-owner fixture users so "UITest Owner" remains
        // the deterministic login when QA follows the shared 1234 credentials.
        let counterAId = try (usersByName["UITest Counter A"] ?? authService.createUser(displayName: "UITest Counter A", pin: "2234"))
        let counterBId = try (usersByName["UITest Counter B"] ?? authService.createUser(displayName: "UITest Counter B", pin: "3234"))

        // Defensive permission upsert for existing databases where prior fixture runs
        // may have left the owner under-scoped.
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT uh.hat_id, ?
                    FROM user_hats uh
                    WHERE uh.user_id = ? AND uh.is_active = 1 AND uh.deleted_at IS NULL
                    """,
                arguments: ["view_warehouse", ownerId]
            )
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                    SELECT uh.hat_id, ?
                    FROM user_hats uh
                    WHERE uh.user_id = ? AND uh.is_active = 1 AND uh.deleted_at IS NULL
                    """,
                arguments: ["perform_audit", ownerId]
            )
        }

        let existingCategoryId: Int64? = try db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM part_categories WHERE name = ? AND deleted_at IS NULL LIMIT 1",
                arguments: ["UITest Warehouse"]
            )
        }
        let categoryId = try existingCategoryId ?? partsService.createCategory(
            name: "UITest Warehouse",
            description: "UI test fixtures"
        )

        let existingPartId: Int64? = try db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM parts WHERE code = ? AND deleted_at IS NULL LIMIT 1",
                arguments: ["UITEST-MUV-001"]
            )
        }
        let partId = try existingPartId ?? partsService.createPart(
            categoryId: categoryId,
            name: "UITest Verification Part",
            code: "UITEST-MUV-001",
            companyCostPrice: 1.25,
            minStockLevel: 1,
            maxStockLevel: 25,
            targetStockLevel: 12
        )

        let stockId = try db.writer.write { dbConn -> Int64 in
            if let existing: Int64 = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1 AND deleted_at IS NULL LIMIT 1",
                arguments: [partId]
            ) {
                try dbConn.execute(
                    sql: "UPDATE stock SET qty = 12, updated_at = datetime('now') WHERE id = ?",
                    arguments: [existing]
                )
                return existing
            }
            try dbConn.execute(
                sql: """
                    INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                    VALUES (?, 'warehouse', 1, 12, datetime('now'))
                    """,
                arguments: [partId]
            )
            return dbConn.lastInsertedRowID
        }

        try warehouseService.recordAuditCount(stockId: stockId, countedQty: 9)
        let sessionId = try warehouseService.createAuditSession(
            scope: "cycle_count",
            zone: "UITest Zone",
            sampleSize: 1,
            includeZeroStock: false,
            notes: "UITest multi-user verification fixture",
            userId: ownerId
        )

        _ = try warehouseService.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 12,
            sessionId: sessionId,
            flaggedBy: ownerId,
            requiredCounts: 2
        )

        try db.writer.write { dbConn in
            // Ensure a deterministic pending assignment for the default UI-test login user.
            let ownerPendingCount = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*)
                    FROM multi_user_audit_assignments
                    WHERE part_id = ? AND audit_session_id = ? AND assigned_user_id = ? AND status = 'pending'
                    """,
                arguments: [partId, sessionId, ownerId]
            ) ?? 0
            if ownerPendingCount == 0 {
                try dbConn.execute(
                    sql: """
                        INSERT INTO multi_user_audit_assignments
                        (part_id, part_name, bin_location, assigned_user_id, assigned_user_name,
                         status, audit_session_id, expected_quantity, notes, created_at)
                        VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)
                        """,
                    arguments: [
                        partId,
                        "UITest Verification Part",
                        "WH-01-A1",
                        ownerId,
                        "UITest Owner",
                        sessionId,
                        12,
                        "Fixture pending assignment",
                        now
                    ]
                )
            }

            // Ensure at least one counted assignment exists for summary-state coverage.
            try dbConn.execute(
                sql: """
                    UPDATE multi_user_audit_assignments
                    SET counted_quantity = 10, counted_at = ?, status = 'counted', notes = 'Fixture counted'
                    WHERE part_id = ? AND audit_session_id = ? AND assigned_user_id = ?
                    """,
                arguments: [now, partId, sessionId, counterAId]
            )
            try dbConn.execute(
                sql: """
                    UPDATE multi_user_audit_assignments
                    SET status = 'pending'
                    WHERE part_id = ? AND audit_session_id = ? AND assigned_user_id = ?
                    """,
                arguments: [partId, sessionId, counterBId]
            )
        }
    }
}
