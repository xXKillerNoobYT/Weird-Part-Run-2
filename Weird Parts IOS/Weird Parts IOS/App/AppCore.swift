import SwiftUI
import Combine
import WiredPartCore

/// Shared application state that owns the database and all services.
///
/// Published as an `@EnvironmentObject` so every view in the tree
/// can access services and the current user without prop-drilling.
@MainActor
final class AppCore: ObservableObject {

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

    // MARK: - Lifecycle

    init() {
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            // Resolve the database path on the main actor (it accesses FileManager),
            // then perform all blocking database work off the main thread to avoid
            // priority inversion (user-interactive main thread waiting on
            // GRDB's default-QoS pool semaphore).
            let path = try Self.databasePath()
            let result = try await Task.detached(priority: .userInitiated) {
                let database = try AppDatabase.openDatabase(atPath: path)
                let auth = AuthService(db: database)
                let settings = SettingsService(db: database)

                let theme = try? settings.getTheme()
                let users = try auth.getActiveUsers()
                let hasProfile = try settings.hasBusinessProfile()

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

            if let theme = result.theme {
                self.theme = theme
            }

            if result.users.isEmpty && !result.hasProfile {
                // Brand-new device — show two-path onboarding
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

            // Run companion auto-discovery cycle in the background
            Task.detached { [partsService] in
                do {
                    try partsService?.runAutoDiscoveryCycle()
                } catch {
                    // Non-critical — auto-discovery failures should not affect app operation
                }
            }
        } catch {
            loadError = error.localizedDescription
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
                return nil // no error
            } else {
                return result.auth.message
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// Log out the current user and return to the login screen.
    func logout() {
        currentUser = nil
        currentToken = nil
        permissions = []
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
                return nil
            } else {
                return result.seed.message
            }
        } catch {
            return error.localizedDescription
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
        db = nil

        // 3. Delete the database file
        try DeviceResetService.deleteDatabaseFile(atPath: dbPath)

        // 4. Clear saved session
        currentUser = nil
        currentToken = nil
        permissions = []

        // 5. Re-bootstrap — will detect no users/profile and set needsOnboarding = true
        isReady = false
        needsBootstrap = false
        needsOnboarding = false
        loadError = nil
        await bootstrap()
    }

    // MARK: - Database Path

    enum AppCoreError: LocalizedError {
        case noDocumentsDirectory
        var errorDescription: String? {
            "Unable to locate app storage directory. Please restart the app."
        }
    }

    /// Returns the path to the SQLite database file in the app's documents directory.
    /// On iOS this is the sandboxed Documents folder.
    static func databasePath() throws -> String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppCoreError.noDocumentsDirectory
        }
        let dir = docs.appendingPathComponent("WiredPart")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wiredpart.sqlite").path
    }
}
