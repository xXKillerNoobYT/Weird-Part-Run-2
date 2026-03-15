import SwiftUI
import GRDB
import WiredPartCore

/// Central application state manager.
///
/// Owns the database connection and all service instances. Published properties
/// drive the root view hierarchy (loading -> bootstrap -> login -> main).
/// Accessed by child views via `@EnvironmentObject`.
@MainActor
final class AppCore: ObservableObject {

    // MARK: - Published State

    @Published var isLoading: Bool = true
    @Published var needsBootstrap: Bool = false
    @Published var currentUser: User? = nil
    @Published var currentToken: String? = nil
    @Published var permissions: [String] = []
    @Published var theme: SettingsService.ThemeSettings = .defaults

    // MARK: - Services

    private(set) var db: AppDatabase?
    private(set) var authService: AuthService?
    private(set) var settingsService: SettingsService?
    private(set) var partsService: PartsService?
    private(set) var warehouseService: WarehouseService?
    private(set) var jobsService: JobsService?
    private(set) var ordersService: OrdersService?
    private(set) var fleetService: FleetService?
    private(set) var peopleService: PeopleService?
    private(set) var schedulingService: SchedulingService?
    private(set) var chatService: ChatService?
    private(set) var notebooksService: NotebooksService?
    private(set) var reportsService: ReportsService?
    private(set) var toolsService: ToolsService?

    // MARK: - Initialization

    /// Open the database, create services, load theme, and determine startup state.
    func initialize() async {
        guard isLoading else { return }

        do {
            let dbPath = Self.databasePath()
            let fileManager = FileManager.default
            let directory = (dbPath as NSString).deletingLastPathComponent
            if !fileManager.fileExists(atPath: directory) {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }

            let database = try AppDatabase.openDatabase(atPath: dbPath)
            self.db = database
            self.authService = AuthService(db: database)
            self.settingsService = SettingsService(db: database)
            self.partsService = PartsService(db: database)
            self.warehouseService = WarehouseService(db: database)
            self.jobsService = JobsService(db: database)
            self.ordersService = OrdersService(db: database)
            self.fleetService = FleetService(db: database)
            self.peopleService = PeopleService(db: database)
            self.schedulingService = SchedulingService(db: database)
            self.chatService = ChatService(db: database)
            self.notebooksService = NotebooksService(db: database)
            self.reportsService = ReportsService(db: database)
            self.toolsService = ToolsService(db: database)

            // Load theme
            if let settings = settingsService {
                self.theme = (try? settings.getTheme()) ?? .defaults
            }

            // Check if this is a first-run (no users exist)
            let users = try authService?.getActiveUsers() ?? []
            if users.isEmpty {
                needsBootstrap = true
            } else {
                // Try to restore a saved session
                restoreSession()
            }
        } catch {
            // On database error, fall back to bootstrap
            print("[AppCore] Initialization error: \(error)")
            needsBootstrap = true
        }

        isLoading = false
    }

    // MARK: - Authentication

    /// Authenticate a user with a 4-digit PIN.
    func login(userId: Int64, pin: String) throws {
        guard let authService else { return }
        let result = try authService.authenticateByPin(userId: userId, pin: pin)
        guard result.success, let user = result.user, let token = result.token else {
            throw LoginError.authFailed(result.message)
        }
        self.currentUser = user
        self.currentToken = token
        self.permissions = (try? authService.getUserPermissions(user.id!)) ?? []
        UserDefaults.standard.set(token, forKey: "auth_token")
    }

    /// Clear current session and return to login screen.
    func logout() {
        currentUser = nil
        currentToken = nil
        permissions = []
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }

    /// Bootstrap the very first admin user on a new device.
    func bootstrap(displayName: String, pin: String) throws {
        guard let authService else { return }
        let result = try authService.seedFirstAdmin(displayName: displayName, pin: pin)
        guard result.success, let user = result.user, let token = result.token else {
            throw LoginError.authFailed(result.message)
        }
        self.currentUser = user
        self.currentToken = token
        self.permissions = (try? authService.getUserPermissions(user.id!)) ?? []
        self.needsBootstrap = false
        UserDefaults.standard.set(token, forKey: "auth_token")
    }

    /// Check whether the current user holds a specific permission key.
    func hasPermission(_ key: String) -> Bool {
        permissions.contains(key)
    }

    /// Reload theme settings from the database and apply them.
    func updateTheme() {
        guard let settingsService else { return }
        self.theme = (try? settingsService.getTheme()) ?? .defaults
    }

    // MARK: - Private Helpers

    /// Attempt to restore a session from a saved token in UserDefaults.
    private func restoreSession() {
        guard let token = UserDefaults.standard.string(forKey: "auth_token"),
              let authService else { return }

        do {
            let profile = try authService.getLocalUserProfile(token: token)
            let user = try authService.getUser(profile.id)
            self.currentUser = user
            self.currentToken = token
            self.permissions = profile.permissions
        } catch {
            // Token expired or invalid — user will need to log in again
            UserDefaults.standard.removeObject(forKey: "auth_token")
        }
    }

    /// Resolve the path to the SQLite database file.
    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("WiredPart", isDirectory: true)
        return appDir.appendingPathComponent("wiredpart.sqlite").path
    }

    // MARK: - Errors

    enum LoginError: LocalizedError {
        case authFailed(String)

        var errorDescription: String? {
            switch self {
            case .authFailed(let message): return message
            }
        }
    }
}
