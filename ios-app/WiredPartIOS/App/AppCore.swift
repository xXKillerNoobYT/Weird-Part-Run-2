import SwiftUI
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
    @Published var currentUser: User?
    @Published var currentToken: String?
    @Published var permissions: [String] = []

    // MARK: - Services (available after init completes)

    private(set) var db: AppDatabase!
    private(set) var authService: AuthService!
    private(set) var settingsService: SettingsService!
    public private(set) var partsService: PartsService?
    public private(set) var warehouseService: WarehouseService?
    public private(set) var jobsService: JobsService?

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

            // Check whether any users exist yet
            let users = try authService.getActiveUsers()
            needsBootstrap = users.isEmpty
            isReady = true
        } catch {
            loadError = error.localizedDescription
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

    /// Check if the current user has a specific permission.
    func hasPermission(_ key: String) -> Bool {
        permissions.contains(key)
    }

    // MARK: - Database Path

    /// Returns the path to the SQLite database file in the app's documents directory.
    /// On iOS this is the sandboxed Documents folder.
    static func databasePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("WiredPart")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wiredpart.sqlite").path
    }
}
