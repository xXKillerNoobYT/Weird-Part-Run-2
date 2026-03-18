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

    private(set) var db: AppDatabase!
    private(set) var authService: AuthService!
    private(set) var settingsService: SettingsService!
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

    // MARK: - Lifecycle

    init() {
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            let path = Self.databasePath()
            db = try AppDatabase.openDatabase(atPath: path)
            authService = AuthService(db: db)
            settingsService = SettingsService(db: db)
            partsService = PartsService(db: db)
            warehouseService = WarehouseService(db: db)
            jobsService = JobsService(db: db)
            ordersService = OrdersService(db: db)
            fleetService = FleetService(db: db)
            peopleService = PeopleService(db: db)
            schedulingService = SchedulingService(db: db)
            chatService = ChatService(db: db)
            notebooksService = NotebooksService(db: db)
            reportsService = ReportsService(db: db)
            toolsService = ToolsService(db: db)

            // Load theme settings
            if let theme = try? settingsService.getTheme() {
                self.theme = theme
            }

            // Check whether any users exist yet
            let users = try authService.getActiveUsers()
            let hasProfile = try settingsService.hasBusinessProfile()

            if users.isEmpty && !hasProfile {
                // Brand-new device — show two-path onboarding
                needsOnboarding = true
                needsBootstrap = false
            } else if users.isEmpty && hasProfile {
                // Business profile exists but no admin yet (edge case)
                needsBootstrap = true
                needsOnboarding = false
            } else {
                needsBootstrap = false
                needsOnboarding = false
            }
            isReady = true
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
    func login(userId: Int64, pin: String) -> String? {
        do {
            let result = try authService.authenticateByPin(userId: userId, pin: pin)
            if result.success {
                currentUser = result.user
                currentToken = result.token
                if let uid = result.user?.id {
                    permissions = try authService.getUserPermissions(uid)
                }
                return nil // no error
            } else {
                return result.message
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
    func seedFirstAdmin(displayName: String, pin: String) -> String? {
        do {
            let result = try authService.seedFirstAdmin(displayName: displayName, pin: pin)
            if result.success {
                currentUser = result.user
                currentToken = result.token
                needsBootstrap = false
                if let uid = result.user?.id {
                    permissions = try authService.getUserPermissions(uid)
                }
                return nil
            } else {
                return result.message
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
        let dbPath = Self.databasePath()

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

    /// Returns the path to the SQLite database file in the app's documents directory.
    /// On iOS this is the sandboxed Documents folder.
    static func databasePath() -> String {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to locate Documents directory — sandboxing issue")
        }
        let dir = docs.appendingPathComponent("WiredPart")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wiredpart.sqlite").path
    }
}
