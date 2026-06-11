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
                    let keyHex = try Self.deviceBootstrapKeyHex()
                    try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)
                    database = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
                    // Remove the .unencrypted.bak file after it has been retained for 7 days.
                    AppDatabase.cleanupStaleUnencryptedBackup(atPath: path)
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
                    #if !DEBUG
                    // Migration failed — try to restore from backup
                    if let backup = backupPath {
                        try? AppDatabase.restoreDatabase(from: backup, to: path)
                        // Retry with restored DB (old schema, but data preserved)
                        self.logger.error("[AppCore] Migration failed, restored from backup. Error: \(error.localizedDescription)")
                    }
                    #endif
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

            if uiTestingMode &&
               ProcessInfo.processInfo.arguments.contains("-UITestingWEI936AutoLogin") &&
               !ProcessInfo.processInfo.arguments.contains("-UITestingForceLogin"),
               let uiTestUser = result.users.first(where: { $0.displayName == "UITest Owner" }),
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
            Task.detached { [toolsService, backgroundTaskService] in
                let taskId = try? backgroundTaskService?.startTask(
                    name: "Tools Scheduled Maintenance",
                    type: "tools_maintenance"
                )
                do {
                    let result = try toolsService?.runScheduledMaintenance()
                    if let taskId {
                        let expiredTrades = result?.expiredTrades ?? 0
                        let updatedScores = result?.updatedConfidenceScores ?? 0
                        try? backgroundTaskService?.completeTask(
                            id: taskId,
                            summary: "Expired \(expiredTrades) trade(s); updated \(updatedScores) confidence score(s)"
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
            let nsError = error as NSError
            logger.error(
                "[AppCore] bootstrap failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(error.localizedDescription, privacy: .public)"
            )
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
    nonisolated static func deviceBootstrapKeyHex(
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> String {
        let uiTestingLaunchFlag = "-UITesting"
        let uiTestingDatabaseKeyHex = "8f1df32f4be04d5fcde1e8e6ddf9187f53a4b68370d5aafc56f0d43f2e9732a1"
        if processArguments.contains(uiTestingLaunchFlag) {
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

        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: keyData
        ]
        #if !targetEnvironment(macCatalyst)
        // kSecAttrAccessible is an iOS-style accessibility class. On Catalyst
        // this can fail with errSecParam on first launch, which blocks DB setup.
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
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
            if shouldUseLocalBootstrapKeyFallback(for: retryAddStatus) {
                return try localFallbackBootstrapKeyHex()
            }
            throw CipherKeyError.keychainAccessFailed(retryAddStatus)
        } else if shouldUseLocalBootstrapKeyFallback(for: addStatus) {
            return try localFallbackBootstrapKeyHex()
        } else if addStatus != errSecSuccess {
            throw CipherKeyError.keychainAccessFailed(addStatus)
        }
        return keyData.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func shouldUseLocalBootstrapKeyFallback(for status: OSStatus) -> Bool {
        guard status == errSecMissingEntitlement else { return false }
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
    /// Local-development fallback when Keychain is unavailable (e.g. unsigned simulator
    /// launch or missing Catalyst entitlement).
    /// Stores a random device key inside the app container to keep DB encryption stable
    /// across launches on the same machine/account.
    nonisolated private static func localFallbackBootstrapKeyHex() throws -> String {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppCoreError.noDocumentsDirectory
        }
        let dir = supportURL.appendingPathComponent("WiredPart", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyURL = dir.appendingPathComponent("local-bootstrap-key.bin")

        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return data.map { String(format: "%02x", $0) }.joined()
        }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard rc == errSecSuccess else {
            throw CipherKeyError.bootstrapKeyGenerationFailed(rc)
        }
        let keyData = Data(keyBytes)
        try keyData.write(to: keyURL, options: .atomic)
        return keyData.map { String(format: "%02x", $0) }.joined()
    }
    #else
    nonisolated private static func localFallbackBootstrapKeyHex() throws -> String {
        throw CipherKeyError.keychainAccessFailed(errSecMissingEntitlement)
    }
    #endif

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

    enum UITestBootstrapError: LocalizedError {
        case partCategoryMissing

        var errorDescription: String? {
            switch self {
            case .partCategoryMissing:
                "UI test bootstrap failed because the required active part category fixture is missing."
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

    nonisolated static func seedUITestingFixtures(db: AppDatabase, authService: AuthService) throws {
        let seedResult = try authService.seedFirstAdmin(displayName: "UITest Owner", pin: "1234")
        let activeUsers = try authService.getActiveUsers()
        let fixtureUserId = seedResult.user?.id ??
            activeUsers.first(where: { $0.displayName == "UITest Owner" })?.id ??
            activeUsers.first?.id

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

            // WEI-1752 / WEI-881 QA fixture: the -UITesting runtime must expose a
            // selectable active job, at least one category, and a deterministic JPO
            // with 2+ selectable line items so the bulk hold/chat smoke can run
            // without manual simulator database surgery.
            if let userId = fixtureUserId {
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

                let fixtureParts: [(code: String, name: String, description: String)] = [
                    ("UITEST-QA-CONDUIT", "UITesting QA Conduit", "Selectable conduit line for bulk JPO hold QA"),
                    ("UITEST-QA-WIRE", "UITesting QA Wire", "Selectable wire line for bulk JPO hold QA")
                ]
                for part in fixtureParts {
                    try dbConn.execute(
                        sql: """
                            INSERT OR IGNORE INTO parts
                            (category_id, part_type, code, name, description, unit_of_measure,
                             company_cost_price, company_markup_percent, is_active, deleted_at,
                             created_at, updated_at)
                            VALUES (?, 'general', ?, ?, ?, 'each', 1.0, 0.0, 1, NULL, datetime('now'), datetime('now'))
                            """,
                        arguments: [categoryId, part.code, part.name, part.description]
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

        if ProcessInfo.processInfo.arguments.contains("-UITestingDispatchBoard") {
            try seedDispatchBoardUITestingFixtures(db: db)
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

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")
        if !ProcessInfo.processInfo.arguments.contains("-UITestingDispatchBoard") {
            UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
        }

        seedWEI936OnboardingStateIfRequested(args: uiTestingArgs, userId: fixtureUserId)
    }

    nonisolated static func uiTestingWEI3144JobMaterialsJobId(db: AppDatabase?) -> Int64? {
        guard ProcessInfo.processInfo.arguments.contains("-UITestingWEI3144JobMaterials"),
              let db
        else { return nil }
        return try? db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM jobs WHERE job_number = 'UITEST-MAT-3144' AND deleted_at IS NULL"
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
            args.contains("-UITestingWEI936DismissedChecklist") ||
            args.contains("-UITestingWEI936NotStarted") ||
            args.contains("-UITestingWEI936Celebration") else { return }

        UserDefaults.standard.removeObject(forKey: "onboarding_checklist_dismissed")

        if let userId {
            let storageKey = "onboarding_progress_\(userId)"
            let shouldActivateTour = !args.contains("-UITestingWEI936NotStarted")
            UserDefaults.standard.set(shouldActivateTour, forKey: storageKey + "_active")

            var completedTasks: Set<String> = []
            if args.contains("-UITestingWEI936RequiredDone") {
                completedTasks.formUnion(["dashboard-view-kpis", "dashboard-tap-kpi"])
            }
            if shouldActivateTour, let data = try? JSONEncoder().encode(completedTasks) {
                UserDefaults.standard.set(data, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        if args.contains("-UITestingWEI936DismissedChecklist") {
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
