import Foundation
import CommonCrypto
import CryptoKit
import GRDB
import Security
import os.log

/// Local Auth Service — PIN authentication + first-run bootstrap.
///
/// Every device authenticates against its own local SQLite DB.
/// User records come from either:
///   1. `seedFirstAdmin()` — the very first device in a new company
///   2. Sync from another device — all subsequent devices
///
/// PIN verification uses PBKDF2-HMAC-SHA256 hashes stored locally. Session tokens
/// are base64-encoded JSON payloads (24-hour expiry).
///
/// Ported from: `src/local/services/auth-service.ts`
public final class AuthService: Sendable {
    private let db: AppDatabase

    /// Structured logger for Keychain / token / auth warnings. Unified log replaces
    /// `print(...)` calls so warnings surface via Console.app/os_log with proper
    /// subsystem filtering and privacy redaction.
    fileprivate static let logger = Logger(subsystem: "com.wiredpart.core", category: "AuthService")

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Types

    /// Result of an authentication attempt.
    public struct AuthResult: Sendable {
        public let success: Bool
        public let user: User?
        public let token: String?
        public let refreshToken: String?
        public let message: String
    }

    /// Decoded session token payload.
    public struct TokenPayload: Codable, Sendable {
        public let sub: Int64
        public let jti: String
        public let iat: Double
        public let exp: Double
        public let type: String
    }

    /// Summary of a user's hat (role).
    public struct HatSummary: Sendable {
        public let id: Int64
        public let name: String
        public let level: Int
    }

    /// Full user profile returned by `getLocalUserProfile`.
    public struct UserProfile: Sendable {
        public let id: Int64
        public let displayName: String
        public let email: String?
        public let phone: String?
        public let avatarURL: String?
        public let certification: String?
        public let hireDate: String?
        public let isActive: Bool
        public let hats: [HatSummary]
        public let permissions: [String]
        public let createdAt: String?
    }

    // MARK: - Brute-Force Protection

    /// Tracks failed login attempts per user to prevent brute-force attacks.
    /// Resets on app restart (acceptable for local-only auth).
    private struct LoginAttemptState {
        var failedCount: Int = 0
        var lockedUntil: Date?
    }

    /// In-memory failed attempt tracker, keyed by user ID.
    /// Protected by attemptLock — safe for concurrent access.
    nonisolated(unsafe) private static var loginAttempts: [Int64: LoginAttemptState] = [:]
    private static let attemptLock = NSLock()

    /// Lockout durations: 3 failures → 5s, 5 → 30s, 8 → 2min, 10+ → 5min
    private static func lockoutDuration(forFailures count: Int) -> TimeInterval? {
        switch count {
        case 0..<3: return nil
        case 3..<5: return 5
        case 5..<8: return 30
        case 8..<10: return 120
        default: return 300
        }
    }

    /// Check if a user is currently locked out. Returns seconds remaining, or nil if not locked.
    public static func lockoutSecondsRemaining(userId: Int64) -> Int? {
        attemptLock.lock()
        defer { attemptLock.unlock() }
        guard let state = loginAttempts[userId],
              let lockedUntil = state.lockedUntil,
              lockedUntil > Date() else { return nil }
        return Int(lockedUntil.timeIntervalSinceNow.rounded(.up))
    }

    /// Record a failed attempt and return lockout seconds (nil if no lockout yet).
    private static func recordFailedAttempt(userId: Int64) -> Int? {
        attemptLock.lock()
        defer { attemptLock.unlock() }
        var state = loginAttempts[userId] ?? LoginAttemptState()
        state.failedCount += 1
        if let duration = lockoutDuration(forFailures: state.failedCount) {
            state.lockedUntil = Date().addingTimeInterval(duration)
            loginAttempts[userId] = state
            return Int(duration)
        }
        loginAttempts[userId] = state
        return nil
    }

    /// Clear failed attempts on successful login.
    private static func clearFailedAttempts(userId: Int64) {
        attemptLock.lock()
        defer { attemptLock.unlock() }
        loginAttempts.removeValue(forKey: userId)
    }

    /// Reset all lockout state. Used by tests that create fresh databases to prevent
    /// inter-test lockout bleed via the static `loginAttempts` dictionary.
    public static func resetAllLoginAttempts() {
        attemptLock.lock()
        defer { attemptLock.unlock() }
        loginAttempts.removeAll()
    }

    // MARK: - Authentication

    /// Authenticate a user by PIN against the local database.
    public func authenticateByPin(userId: Int64, pin: String) throws -> AuthResult {
        // Check lockout before attempting authentication
        if let seconds = Self.lockoutSecondsRemaining(userId: userId) {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "Too many failed attempts. Try again in \(seconds)s.")
        }

        let user: User? = try db.writer.read { dbConnection in
            try User.fetchOne(
                dbConnection,
                sql: "SELECT * FROM users WHERE id = ? AND is_active = 1 AND deleted_at IS NULL",
                arguments: [userId]
            )
        }

        guard let user else {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "User not found or inactive")
        }

        guard let pinHash = user.pinHash, pinHash != "__PLACEHOLDER_HASH__" else {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "PIN not configured. Sync with shop first.")
        }

        let isValid = Self.verifyPinLocally(pin: pin, storedHash: pinHash, salt: user.pinSalt)
        guard isValid else {
            if let lockoutSeconds = Self.recordFailedAttempt(userId: userId) {
                return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "Invalid PIN. Locked for \(lockoutSeconds)s.")
            }
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "Invalid PIN")
        }

        guard let userId = user.id else {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "User record missing ID")
        }

        // Migration path: upgrade legacy hashes to PBKDF2 on successful login.
        // Tier 1 (no salt) and Tier 2 (iterated SHA-256) both get upgraded transparently.
        let needsUpgrade = user.pinSalt == nil || !Self.isPBKDF2Hash(pinHash)
        if needsUpgrade {
            let newSalt = user.pinSalt ?? Self.generateSalt()
            let newHash = Self.hashPin(pin, salt: newSalt)
            let now = Self.currentTimestamp()
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: "UPDATE users SET pin_hash = ?, pin_salt = ?, updated_at = ? WHERE id = ?",
                    arguments: [newHash, newSalt, now, userId]
                )
            }
        }

        Self.clearFailedAttempts(userId: userId)
        let session = try issueSessionTokens(forUserId: userId, parentRefreshId: nil)
        return AuthResult(success: true, user: user, token: session.accessToken, refreshToken: session.refreshToken, message: "Authenticated")
    }

    /// Get list of active users for the login screen.
    public func getActiveUsers() throws -> [User] {
        try db.writer.read { dbConnection in
            try User.fetchAll(
                dbConnection,
                sql: "SELECT * FROM users WHERE is_active = 1 AND deleted_at IS NULL ORDER BY display_name ASC"
            )
        }
    }

    // MARK: - Bootstrap

    /// Bootstrap a brand-new company database on the very first device.
    ///
    /// Creates:
    ///  - 7 built-in hats (Admin -> Grunt) with permission keys
    ///  - 1 admin user with the given display name and PIN
    ///  - Assigns the Admin hat to that user
    ///  - Seeds default settings
    ///
    /// This is the ONLY way to start from zero. All subsequent devices
    /// receive data by syncing from this one (or any peer that already has it).
    public func seedFirstAdmin(displayName: String, pin: String) throws -> AuthResult {
        // Guard: don't re-seed if users already exist
        let existingCount = try db.writer.read { dbConnection -> Int in
            try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM users") ?? 0
        }

        if existingCount > 0 {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "Users already exist. Seed aborted.")
        }

        let now = Self.currentTimestamp()
        let salt = Self.generateSalt()
        let pinHash = Self.hashPin(pin, salt: salt)

        try db.writer.write { dbConnection in
            // 1. Create built-in hats
            let hats: [(name: String, level: Int, description: String)] = [
                ("Admin",      100, "Full system access"),
                ("Manager",     80, "Most permissions except system settings"),
                ("Office",      60, "Ordering, reports, scheduling"),
                ("Lead",        50, "Field lead with scoped job management"),
                ("Worker",      30, "Basic field access"),
                ("Apprentice",  20, "Restricted field access"),
                ("Grunt",       10, "Minimal access"),
            ]

            for hat in hats {
                try dbConnection.execute(
                    sql: """
                        INSERT OR IGNORE INTO hats (name, description, level, is_builtin, created_at)
                        VALUES (?, ?, ?, 1, ?)
                        """,
                    arguments: [hat.name, hat.description, hat.level, now]
                )
            }

            // 2. Assign permission keys to each hat
            let permissionMap = Self.defaultPermissionMap()
            for (hatName, perms) in permissionMap {
                for perm in perms {
                    try dbConnection.execute(
                        sql: """
                            INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
                            SELECT id, ? FROM hats WHERE name = ?
                            """,
                        arguments: [perm, hatName]
                    )
                }
            }

            // 3. Create the first admin user
            try dbConnection.execute(
                sql: """
                    INSERT INTO users (display_name, pin_hash, pin_salt, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, 1, ?, ?)
                    """,
                arguments: [displayName, pinHash, salt, now, now]
            )

            let userId = dbConnection.lastInsertedRowID

            // 4. Assign Admin hat
            try dbConnection.execute(
                sql: """
                    INSERT INTO user_hats (user_id, hat_id, is_active)
                    SELECT ?, id, 1 FROM hats WHERE name = 'Admin'
                    """,
                arguments: [userId]
            )

            // 5. Seed default settings
            let defaults: [(key: String, value: String, category: String)] = [
                ("company_name", "\(displayName)'s Company", "general"),
                ("auto_lock_minutes", "15", "security"),
                ("stale_data_hours", "4", "sync"),
                ("archive_completed_days", "90", "data"),
            ]
            for setting in defaults {
                try dbConnection.execute(
                    sql: """
                        INSERT OR IGNORE INTO settings (key, value, category, updated_at)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [setting.key, setting.value, setting.category, now]
                )
            }

            // 6. Log to activity log
            try dbConnection.execute(
                sql: """
                    INSERT INTO activity_log (user_id, action, entity_type, entity_id, details, timestamp)
                    VALUES (?, 'first_admin_setup', 'user', ?, 'First device bootstrap', ?)
                    """,
                arguments: [userId, userId, now]
            )
        }

        // Fetch the newly created user
        let user = try db.writer.read { dbConnection -> User? in
            try User.fetchOne(
                dbConnection,
                sql: "SELECT * FROM users WHERE display_name = ? ORDER BY id DESC LIMIT 1",
                arguments: [displayName]
            )
        }

        guard let user, let userId = user.id else {
            return AuthResult(success: false, user: nil, token: nil, refreshToken: nil, message: "Failed to create admin user")
        }

        let session = try issueSessionTokens(forUserId: userId, parentRefreshId: nil)
        return AuthResult(success: true, user: user, token: session.accessToken, refreshToken: session.refreshToken, message: "Company database initialized. Welcome!")
    }

    // MARK: - User Queries

    /// Get a single user by ID.
    public func getUser(_ userId: Int64) throws -> User? {
        try db.writer.read { dbConnection in
            try User.fetchOne(
                dbConnection,
                sql: "SELECT * FROM users WHERE id = ?",
                arguments: [userId]
            )
        }
    }

    /// Get permissions for a user (from user_hats + hat_permissions).
    ///
    /// Only returns permissions for users who are currently active (not soft-deleted).
    public func getUserPermissions(_ userId: Int64) throws -> [String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: """
                    SELECT DISTINCT hp.permission_key
                    FROM user_hats uh
                    JOIN users u ON u.id = uh.user_id
                    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                    WHERE uh.user_id = ?
                      AND uh.is_active = 1 AND uh.deleted_at IS NULL
                      AND u.deleted_at IS NULL AND u.is_active = 1
                    """,
                arguments: [userId]
            )
            return rows.compactMap { $0["permission_key"] as? String }
        }
    }

    /// Check if user has a specific permission.
    ///
    /// Returns false for soft-deleted users (`users.deleted_at IS NOT NULL`) or
    /// inactive users (`users.is_active = 0`) even if their hat assignments remain active.
    /// This closes the backdoor where a terminated user could still pass the permission gate
    /// because their `user_hats` rows were not cascaded at termination time.
    public func hasPermission(_ userId: Int64, permissionKey: String) throws -> Bool {
        try db.writer.read { dbConnection in
            let count = try Int.fetchOne(
                dbConnection,
                sql: """
                    SELECT COUNT(*) FROM user_hats uh
                    JOIN users u ON u.id = uh.user_id
                    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                    WHERE uh.user_id = ?
                      AND uh.is_active = 1 AND uh.deleted_at IS NULL
                      AND u.deleted_at IS NULL AND u.is_active = 1
                      AND hp.permission_key = ?
                    LIMIT 1
                    """,
                arguments: [userId, permissionKey]
            ) ?? 0
            return count > 0
        }
    }

    /// Soft-delete a user and cascade-deactivate their hat assignments.
    ///
    /// Runs in a single write transaction so the cascade is atomic:
    /// - `users.deleted_at` and `users.is_active = 0` are set together.
    /// - All `user_hats` rows for the user are deactivated simultaneously.
    ///
    /// After this call, `hasPermission` will return `false` for the user,
    /// even if the `user_hats` rows had already been cleaned up separately.
    public func softDeleteUser(userId: Int64) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    UPDATE users
                    SET deleted_at = datetime('now'),
                        is_active  = 0,
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [userId]
            )
            // Defense-in-depth: also deactivate hat assignments so they're
            // visually clean in admin UI and don't survive if a future query
            // accidentally omits the users JOIN.
            try dbConnection.execute(
                sql: """
                    UPDATE user_hats
                    SET is_active  = 0,
                        deleted_at = datetime('now')
                    WHERE user_id = ? AND deleted_at IS NULL
                    """,
                arguments: [userId]
            )
        }
    }

    /// Get all permission keys for a specific hat.
    public func getHatPermissions(_ hatId: Int64) throws -> [String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: "SELECT permission_key FROM hat_permissions WHERE hat_id = ?",
                arguments: [hatId]
            )
            return rows.map { $0["permission_key"] as String }
        }
    }

    /// Add a permission key to a hat.
    public func addHatPermission(hatId: Int64, permissionKey: String) throws {
        guard !permissionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.requiredFieldEmpty("permissionKey")
        }
        try db.writer.write { dbConnection in
            // Guard: the hat must exist — `hats` is not soft-deletable (hard-delete only
            // via SettingsService), but the FK constraint still requires existence check
            // to avoid silently INSERTing orphan permissions the permission engine
            // would then refuse to apply.
            let hatExists = (try Int.fetchOne(dbConnection, sql: """
                SELECT COUNT(*) FROM hats WHERE id = ?
                """, arguments: [hatId]) ?? 0) > 0
            guard hatExists else { throw AuthError.hatNotFound(hatId) }

            try dbConnection.execute(
                sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)",
                arguments: [hatId, permissionKey]
            )
        }
    }

    /// Remove a permission key from a hat.
    public func removeHatPermission(hatId: Int64, permissionKey: String) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "DELETE FROM hat_permissions WHERE hat_id = ? AND permission_key = ?",
                arguments: [hatId, permissionKey]
            )
        }
    }

    /// Get hat names for a user (for UserPicker display).
    public func getUserHatNames(_ userId: Int64) throws -> [String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: """
                    SELECT h.name FROM user_hats uh
                    JOIN hats h ON h.id = uh.hat_id
                    WHERE uh.user_id = ? AND uh.is_active = 1 AND uh.deleted_at IS NULL
                    ORDER BY h.level DESC
                    """,
                arguments: [userId]
            )
            return rows.map { $0["name"] as String }
        }
    }

    /// Get hat summaries for a user (for UserProfile).
    public func getUserHats(_ userId: Int64) throws -> [HatSummary] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: """
                    SELECT h.id, h.name, h.level FROM user_hats uh
                    JOIN hats h ON h.id = uh.hat_id
                    WHERE uh.user_id = ? AND uh.is_active = 1 AND uh.deleted_at IS NULL
                    ORDER BY h.level DESC
                    """,
                arguments: [userId]
            )
            return rows.map {
                HatSummary(
                    id: $0["id"] as Int64,
                    name: $0["name"] as String,
                    level: $0["level"] as Int
                )
            }
        }
    }

    /// Build a full UserProfile from a local token.
    public func getLocalUserProfile(token: String) throws -> UserProfile {
        guard let payload = Self.parseLocalToken(token), payload.type == "local_access" else {
            throw AuthError.invalidToken
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        guard payload.exp > nowMs else {
            throw AuthError.tokenExpired
        }
        guard try isTokenActive(tokenId: payload.jti, expectedType: "local_access") else {
            throw AuthError.sessionRevoked
        }

        guard let user = try getUser(payload.sub) else {
            throw AuthError.userNotFound
        }

        let hats = try getUserHats(payload.sub)
        let permissions = try getUserPermissions(payload.sub)

        guard let profileId = user.id else {
            throw AuthError.userNotFound
        }
        return UserProfile(
            id: profileId,
            displayName: user.displayName,
            email: user.email,
            phone: user.phone,
            avatarURL: user.avatarUrl,
            certification: user.certification,
            hireDate: user.hireDate,
            isActive: user.isActive == 1,
            hats: hats,
            permissions: permissions,
            createdAt: user.createdAt
        )
    }

    // MARK: - Auth Errors

    /// Returns true when the error is a "no such table" SQLite error.
    /// Used to gracefully handle first-launch states before all migrations run.
    private static func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }

    public enum AuthError: Error, Sendable, Equatable {
        case invalidToken
        case tokenExpired
        case userNotFound
        case sessionRevoked
        case requiredFieldEmpty(String)
        case invalidPin(String)
        case hatNotFound(Int64)
    }

    /// Rotate a refresh token and return a fresh access+refresh pair.
    public func refreshLocalSession(refreshToken: String) throws -> (accessToken: String, refreshToken: String) {
        guard let payload = Self.parseLocalToken(refreshToken), payload.type == "local_refresh" else {
            throw AuthError.invalidToken
        }
        let nowMs = Date().timeIntervalSince1970 * 1000
        guard payload.exp > nowMs else {
            throw AuthError.tokenExpired
        }
        guard try isTokenActive(tokenId: payload.jti, expectedType: "local_refresh") else {
            throw AuthError.sessionRevoked
        }

        let tokens = try Self.makeSessionTokens(forUserId: payload.sub)
        try db.writer.write { dbConn in
            let now = Self.currentTimestamp()
            try Self.revokeTokenById(payload.jti, in: dbConn, revokedAt: now)
            try Self.insertSessionTokens(tokens, userId: payload.sub, parentRefreshId: payload.jti, createdAt: now, in: dbConn)
        }
        return (tokens.access, tokens.refresh)
    }

    /// Revoke an access or refresh token string.
    public func revokeLocalSession(token: String) throws {
        guard let payload = Self.parseLocalToken(token) else {
            throw AuthError.invalidToken
        }
        try revokeTokenById(payload.jti)
    }

    // MARK: - Security & Device Administration

    /// Summary of a registered device.
    public struct RegisteredDevice: Sendable {
        public let id: String
        public let name: String
        public let deviceType: String
        public let assignedUser: String
        public let lastSeenAt: String?
        public let status: String
    }

    /// Summary of an active (trusted) session.
    public struct ActiveSession: Sendable {
        public let id: String
        public let userId: String
        public let userName: String
        public let createdAt: String
    }

    /// List registered devices with assigned user names.
    public func listRegisteredDevices() throws -> [RegisteredDevice] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT d.id, d.device_name, d.device_fingerprint, d.last_seen,
                           COALESCE(u.display_name, 'Unassigned') AS assigned_user
                    FROM devices d
                    LEFT JOIN users u ON u.id = d.assigned_user_id AND u.deleted_at IS NULL
                    WHERE d.deleted_at IS NULL
                    ORDER BY d.last_seen DESC
                """)
                return rows.map { row in
                    let lastSeen = row["last_seen"] as? String
                    return RegisteredDevice(
                        id: "\(row["id"] as Int64? ?? 0)",
                        name: row["device_name"] as? String ?? "Unknown",
                        deviceType: row["device_fingerprint"] as? String ?? "unknown",
                        assignedUser: row["assigned_user"] as? String ?? "Unassigned",
                        lastSeenAt: lastSeen,
                        status: Self.isRecentlyOnline(lastSeen) ? "online" : "offline"
                    )
                }
            }
        } catch {
            if Self.isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// List active (trusted, non-deactivated) sessions from the device registry.
    public func listActiveSessions() throws -> [ActiveSession] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT dr.rowid AS id, dr.device_id, dr.created_at,
                           COALESCE(dr.device_name, 'Unknown') AS user_name
                    FROM _device_registry dr
                    WHERE dr.is_trusted = 1 AND dr.is_deactivated = 0
                    ORDER BY dr.last_seen_at DESC
                """)
                return rows.map { row in
                    ActiveSession(
                        id: "\(row["id"] as Int64? ?? 0)",
                        userId: row["device_id"] as? String ?? "unknown",
                        userName: row["user_name"] as? String ?? "Unknown",
                        createdAt: row["created_at"] as? String ?? "Unknown"
                    )
                }
            }
        } catch {
            if Self.isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Force-deactivate a trusted device session by its rowid in the device registry.
    /// The deactivation is also appended to `_change_log` so peers can sync the revocation.
    public func deactivateSession(sessionId: String) throws {
        try db.writer.write { dbConnection in
            guard let deviceId = try String.fetchOne(
                dbConnection,
                sql: "SELECT device_id FROM _device_registry WHERE rowid = ?",
                arguments: [sessionId]
            ) else {
                return
            }
            try dbConnection.execute(
                sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE device_id = ?",
                arguments: [deviceId]
            )

            let changedFieldsJSON = #"{"is_deactivated":1,"device_id":"\#(deviceId)"}"#
            try dbConnection.execute(
                sql: """
                    INSERT INTO _change_log
                        (table_name, record_id, operation, device_id, changed_fields, timestamp)
                    VALUES ('_device_registry', 0, 'UPDATE', ?, ?, datetime('now'))
                    """,
                arguments: [deviceId, changedFieldsJSON]
            )
        }
    }

    /// Check if a last_seen timestamp is within the last 5 minutes.
    private static func isRecentlyOnline(_ lastSeen: String?) -> Bool {
        guard let lastSeen, !lastSeen.isEmpty else { return false }
        guard let date = CoreFormatters.parseDateTime(lastSeen) else { return false }
        return Date().timeIntervalSince(date) < 300
    }

    // MARK: - PIN Upgrade Tracking

    /// Count of active users NOT yet on the current PBKDF2 KDF.
    /// Includes both legacy tier 1 (no salt) and tier 2 (iterated SHA-256).
    /// These users will be upgraded automatically on their next successful login.
    /// Returns 0 once all users have logged in since the PBKDF2 upgrade.
    ///
    /// Admins can use this to monitor upgrade progress in the People → Permissions area.
    public func getLegacyHashedUserCount() throws -> Int {
        try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*) FROM users
                    WHERE is_active = 1
                      AND deleted_at IS NULL
                      AND pin_hash NOT LIKE 'pbkdf2$%'
                      AND pin_hash NOT LIKE '$2b$%'
                      AND pin_hash != '__PLACEHOLDER_HASH__'
                    """
            ) ?? 0
        }
    }

    /// Active users not yet on PBKDF2, returned as (id, displayName) pairs.
    /// Admins can surface these in the People → Permissions area to prompt affected users to log in
    /// and trigger the automatic PBKDF2 migration.
    public func getLegacyHashedUsers() throws -> [(id: Int64, displayName: String)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT id, display_name FROM users
                    WHERE is_active = 1
                      AND deleted_at IS NULL
                      AND pin_hash NOT LIKE 'pbkdf2$%'
                      AND pin_hash NOT LIKE '$2b$%'
                      AND pin_hash != '__PLACEHOLDER_HASH__'
                    ORDER BY display_name
                    """
            )
            return rows.map { (id: $0["id"], displayName: $0["display_name"]) }
        }
    }

    // MARK: - User Management

    /// Create a new user (employee). Returns the new user's ID.
    @discardableResult
    public func createUser(
        displayName: String,
        pin: String,
        email: String? = nil,
        phone: String? = nil
    ) throws -> Int64 {
        // Validate inputs: display name must be non-blank; PIN must be 4–8 digits.
        // Previously a blank displayName would create a login-screen entry the user
        // couldn't select, and a too-short PIN bypassed lockout timing.
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.requiredFieldEmpty("displayName")
        }
        let trimmedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPin.count >= 4 && trimmedPin.count <= 8,
              trimmedPin.allSatisfy({ $0.isNumber }) else {
            throw AuthError.invalidPin("PIN must be 4–8 digits")
        }

        let salt = Self.generateSalt()
        let pinHash = Self.hashPin(pin, salt: salt)
        let now = Self.currentTimestamp()
        return try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO users (display_name, pin_hash, pin_salt, email, phone, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, 1, ?, ?)
                    """,
                arguments: [displayName, pinHash, salt, email, phone, now, now]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // MARK: - PIN Change

    /// Change a user's PIN.
    ///
    /// Verifies the old PIN before making any changes. On success:
    /// 1. Updates the user's `pin_hash` and `pin_salt` to the new PIN.
    ///
    /// The SQLCipher app database remains encrypted with the device bootstrap key.
    /// Re-keying it to a per-user PIN would make the next launch fail unless startup
    /// had a pre-open unlock flow that can select the current DB key before login.
    ///
    /// - Parameters:
    ///   - userId: The user whose PIN is being changed.
    ///   - oldPin: The current PIN (must authenticate successfully).
    ///   - newPin: The new PIN (4–8 digits, same rules as `createUser`).
    /// - Throws: `AuthError.invalidPin` if `oldPin` is wrong.
    ///           `AuthError.requiredFieldEmpty` if `newPin` is empty.
    @discardableResult
    public func changePin(userId: Int64, oldPin: String, newPin: String) throws -> Bool {
        // Validate new PIN.
        let trimmed = newPin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.requiredFieldEmpty("newPin")
        }
        guard trimmed.count >= 4 && trimmed.count <= 8, trimmed.allSatisfy({ $0.isNumber }) else {
            throw AuthError.invalidPin("New PIN must be 4–8 digits")
        }

        // Verify old PIN against the DB (uses existing brute-force protection).
        let authResult = try authenticateByPin(userId: userId, pin: oldPin)
        guard authResult.success else {
            throw AuthError.invalidPin(authResult.message)
        }

        // Persist new PIN hash using the trimmed (normalised) PIN so PIN validation
        // and key derivation are always consistent — no whitespace variants.
        let newSalt = Self.generateSalt()
        let newHash = Self.hashPin(trimmed, salt: newSalt)
        let now = Self.currentTimestamp()
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET pin_hash = ?, pin_salt = ?, updated_at = ? WHERE id = ?",
                arguments: [newHash, newSalt, now, userId]
            )
        }

        return true
    }

    // MARK: - Internal Helpers

    /// Verify a PIN against a stored hash.
    /// Supports three formats in order of preference:
    ///   1. PBKDF2  — `pbkdf2$<iterations>$<hex>`  (current, per-user salt in `pin_salt`)
    ///   2. Iterated SHA-256 — 64-char hex with per-user salt (legacy tier 2)
    ///   3. Single SHA-256 — 64-char hex with fixed "wiredpart" salt (legacy tier 1, no `pin_salt`)
    /// Bcrypt hashes (synced from another system) are not verifiable locally.
    static func verifyPinLocally(pin: String, storedHash: String, salt: String?) -> Bool {
        // Bcrypt — can't verify offline
        if storedHash.hasPrefix("$2b$") || storedHash.hasPrefix("$2a$") {
            return false
        }

        // PBKDF2 format: pbkdf2$<iterations>$<hex>
        if storedHash.hasPrefix("pbkdf2$"), let salt {
            return verifyPBKDF2(pin: pin, storedHash: storedHash, salt: salt)
        }

        if let salt {
            // Legacy tier 2: iterated SHA-256 with per-user salt
            let computed = iteratedSHA256Pin(pin, salt: salt)
            return computed == storedHash
        } else {
            // Legacy tier 1: single SHA-256 with fixed salt
            let computed = legacyHashPin(pin)
            return computed == storedHash
        }
    }

    // MARK: - PBKDF2 Hashing (current)

    /// Default PBKDF2 iteration count — OWASP 2023 minimum for HMAC-SHA256.
    static let pbkdf2Iterations: UInt32 = 600_000

    /// Hash a PIN with PBKDF2-HMAC-SHA256. Returns `pbkdf2$<iterations>$<hex>`.
    /// The per-user salt is stored separately in the `pin_salt` column.
    static func hashPin(_ pin: String, salt: String) -> String {
        let password = Array(pin.utf8)
        let saltBytes = Array(salt.utf8)
        var derivedKey = [UInt8](repeating: 0, count: 32) // 256-bit output
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            pbkdf2Iterations,
            &derivedKey, derivedKey.count
        )
        guard status == kCCSuccess else {
            // Fallback should never happen — log and use iterated SHA-256
            Self.logger.error("PBKDF2 failed with status \(status, privacy: .public), falling back to iterated SHA-256")
            return iteratedSHA256Pin(pin, salt: salt)
        }
        let hex = derivedKey.map { String(format: "%02x", $0) }.joined()
        return "pbkdf2$\(pbkdf2Iterations)$\(hex)"
    }

    /// Verify a PIN against a PBKDF2 hash string.
    private static func verifyPBKDF2(pin: String, storedHash: String, salt: String) -> Bool {
        let parts = storedHash.split(separator: "$")
        guard parts.count == 3,
              parts[0] == "pbkdf2",
              let iterations = UInt32(parts[1]) else { return false }
        let expectedHex = String(parts[2])

        guard let expectedBytes = hexBytes(expectedHex) else { return false }
        let password = Array(pin.utf8)
        let saltBytes = Array(salt.utf8)
        var derivedKey = [UInt8](repeating: 0, count: expectedBytes.count)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derivedKey, derivedKey.count
        )
        guard status == kCCSuccess else { return false }
        return constantTimeEqual(derivedKey, expectedBytes)
    }

    // MARK: - Legacy Hash Functions (verification only)

    /// Iterated SHA-256 with per-user salt (legacy tier 2, pre-PBKDF2).
    /// Kept for verifying existing hashes; new hashes use PBKDF2.
    static func iteratedSHA256Pin(_ pin: String, salt: String) -> String {
        let input = Data((pin + ":" + salt).utf8)
        var hash = SHA256.hash(data: input)
        for _ in 0..<10_000 {
            hash = SHA256.hash(data: Data(hash))
        }
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Legacy fixed-salt hash for backward compatibility during migration.
    /// Used only to verify old PINs before re-hashing with PBKDF2.
    static func legacyHashPin(_ pin: String) -> String {
        let data = Data((pin + ":wiredpart").utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate a random salt for PIN hashing.
    static func generateSalt() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    /// Check if a stored hash is already using the current PBKDF2 KDF.
    static func isPBKDF2Hash(_ hash: String) -> Bool {
        hash.hasPrefix("pbkdf2$")
    }

    /// Device-specific signing key. Persisted in the Keychain so tokens survive app
    /// restarts. On first launch a cryptographically random 256-bit key is generated
    /// and stored; subsequent launches load the same key. Wiping the device or
    /// reinstalling the app generates a fresh key (invalidating old tokens, which
    /// is the expected behavior).
    private static let signingKey: SymmetricKey = {
        let service = "com.wiredpart.token-signing-key"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            // Fix #231: migrate any pre-existing key to the tightened accessibility tier.
            // SecItemCopyMatching doesn't tell us which tier the item was stored under,
            // so we unconditionally update — SecItemUpdate is a no-op if attributes match,
            // and a tier upgrade if they don't. Failure is non-fatal (key still works).
            let migrateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service
            ]
            let migrateAttrs: [CFString: Any] = [
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            _ = SecItemUpdate(migrateQuery as CFDictionary, migrateAttrs as CFDictionary)
            return SymmetricKey(data: data)
        }
        // Generate a new 256-bit key and persist it.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyData = Data(keyBytes)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData: keyData,
            // Fix #231: WhenUnlockedThisDeviceOnly narrows the window — the signing key
            // is only readable while the screen is actively unlocked, not after first-unlock-since-boot.
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            // Key generated but not persisted — tokens will invalidate on next app launch.
            // errSecDuplicateItem is benign (item was added between our read and write).
            AuthService.logger.warning("SecItemAdd failed (OSStatus \(addStatus)) — signing key in memory only. Tokens will not survive app restart.")
        }
        return SymmetricKey(data: keyData)
    }()

    /// Generate a signed local session token (base64 payload + HMAC-SHA256 signature).
    static func generateLocalToken(userId: Int64) -> String? {
        generateToken(userId: userId, type: "local_access", ttlMs: 15 * 60 * 1000)
    }

    static func generateLocalRefreshToken(userId: Int64) -> String? {
        generateToken(userId: userId, type: "local_refresh", ttlMs: 7 * 24 * 60 * 60 * 1000)
    }

    private static func generateToken(userId: Int64, type: String, ttlMs: Double) -> String? {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let payload = TokenPayload(
            sub: userId,
            jti: UUID().uuidString.lowercased(),
            iat: nowMs,
            exp: nowMs + ttlMs,
            type: type
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        let payloadB64 = data.base64EncodedString()
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: signingKey)
        let sigB64 = Data(signature).base64EncodedString()
        return "\(payloadB64).\(sigB64)"
    }

    /// Parse and verify a signed local token. Returns nil if invalid or tampered.
    /// Legacy unsigned token path removed 2026-04-08 — all tokens generated since
    /// PE-008a (2026-03-31) are HMAC-signed. Unsigned tokens are now rejected.
    static func parseLocalToken(_ token: String) -> TokenPayload? {
        let parts = token.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let payloadB64 = String(parts[0])
        let sigB64 = String(parts[1])
        guard let sigData = Data(base64Encoded: sigB64) else { return nil }
        guard HMAC<SHA256>.isValidAuthenticationCode(sigData, authenticating: Data(payloadB64.utf8), using: signingKey) else { return nil }

        guard let data = Data(base64Encoded: payloadB64) else { return nil }
        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else { return nil }
        guard payload.type == "local_access" || payload.type == "local_refresh" else { return nil }
        return payload
    }

    private struct SessionTokenPair {
        let access: String
        let refresh: String
        let accessPayload: TokenPayload
        let refreshPayload: TokenPayload
    }

    private static func makeSessionTokens(forUserId userId: Int64) throws -> SessionTokenPair {
        guard let access = Self.generateLocalToken(userId: userId),
              let refresh = Self.generateLocalRefreshToken(userId: userId),
              let accessPayload = Self.parseLocalToken(access),
              let refreshPayload = Self.parseLocalToken(refresh) else {
            throw AuthError.invalidToken
        }
        return SessionTokenPair(access: access, refresh: refresh, accessPayload: accessPayload, refreshPayload: refreshPayload)
    }

    private func issueSessionTokens(forUserId userId: Int64, parentRefreshId: String?) throws -> (accessToken: String, refreshToken: String) {
        let tokens = try Self.makeSessionTokens(forUserId: userId)

        try db.writer.write { dbConn in
            let now = Self.currentTimestamp()
            try Self.insertSessionTokens(tokens, userId: userId, parentRefreshId: parentRefreshId, createdAt: now, in: dbConn)
        }
        return (tokens.access, tokens.refresh)
    }

    private func revokeTokenById(_ tokenId: String) throws {
        try db.writer.write { dbConn in
            try Self.revokeTokenById(tokenId, in: dbConn, revokedAt: Self.currentTimestamp())
        }
    }

    private static func insertSessionTokens(
        _ tokens: SessionTokenPair,
        userId: Int64,
        parentRefreshId: String?,
        createdAt: String,
        in dbConn: Database
    ) throws {
        try dbConn.execute(
            sql: """
                INSERT INTO auth_token_sessions (token_id, user_id, token_type, parent_refresh_id, expires_at_ms, revoked_at, created_at)
                VALUES (?, ?, 'local_access', ?, ?, NULL, ?)
            """,
            arguments: [tokens.accessPayload.jti, userId, tokens.refreshPayload.jti, tokens.accessPayload.exp, createdAt]
        )
        try dbConn.execute(
            sql: """
                INSERT INTO auth_token_sessions (token_id, user_id, token_type, parent_refresh_id, expires_at_ms, revoked_at, created_at)
                VALUES (?, ?, 'local_refresh', ?, ?, NULL, ?)
            """,
            arguments: [tokens.refreshPayload.jti, userId, parentRefreshId, tokens.refreshPayload.exp, createdAt]
        )
    }

    private static func revokeTokenById(_ tokenId: String, in dbConn: Database, revokedAt: String) throws {
        try dbConn.execute(
            sql: "UPDATE auth_token_sessions SET revoked_at = ? WHERE token_id = ?",
            arguments: [revokedAt, tokenId]
        )
    }

    private func isTokenActive(tokenId: String, expectedType: String) throws -> Bool {
        try db.writer.read { dbConn in
            let row = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT revoked_at, expires_at_ms
                    FROM auth_token_sessions
                    WHERE token_id = ? AND token_type = ?
                """,
                arguments: [tokenId, expectedType]
            )
            guard let row else { return false }
            if (row["revoked_at"] as String?) != nil { return false }
            let nowMs = Date().timeIntervalSince1970 * 1000
            let expMs = row["expires_at_ms"] as Double? ?? 0
            guard expMs > nowMs else { return false }
            return try !isCurrentDeviceDeactivated(in: dbConn)
        }
    }

    private func isCurrentDeviceDeactivated(in dbConn: Database) throws -> Bool {
        let currentDeviceId: String?
        do {
            currentDeviceId = try String.fetchOne(
                dbConn,
                sql: "SELECT value FROM settings WHERE key = 'device_id'"
            )
        } catch {
            if Self.isTableNotFoundError(error) { return false }
            throw error
        }

        guard let currentDeviceId else { return false }

        do {
            let isDeactivated = try Int.fetchOne(
                dbConn,
                sql: "SELECT is_deactivated FROM _device_registry WHERE device_id = ?",
                arguments: [currentDeviceId]
            ) ?? 0
            return isDeactivated != 0
        } catch {
            if Self.isTableNotFoundError(error) { return false }
            throw error
        }
    }

    /// Current ISO-8601-ish timestamp (matching the TS format: "YYYY-MM-DD HH:MM:SS").
    private static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    // MARK: - Default Permission Map

    private static func defaultPermissionMap() -> [String: [String]] {
        [
            "Admin": [
                "view_parts_catalog", "edit_parts_catalog", "edit_pricing", "show_dollar_values",
                "manage_deprecation", "view_warehouse", "manage_warehouse", "move_stock_warehouse",
                "view_trucks", "manage_trucks", "move_stock_truck", "view_jobs", "manage_jobs",
                "clock_in_out", "consume_parts_any_job", "view_labor", "manage_labor",
                "view_orders", "manage_orders", "approve_returns", "view_people", "manage_people",
                "view_reports", "export_reports", "manage_settings", "manage_devices",
                "manage_templates", "manage_notebooks", "perform_audit", "manager_override", "view_activity_log",
                "view_fleet", "manage_fleet", "log_fleet", "view_tools", "manage_tools",
                "view_scheduling", "manage_scheduling", "manage_dispatch",
                "view_schedule", "manage_schedule", "dispatch_employees",
                "manage_time_off", "manage_subcontractors",
                "view_chat", "manage_chat", "moderate_chat",
                "use_chat", "ask_qa", "send_rfi",
                "view_customers", "view_contractors",
                "manage_remote_sync",
                // 39A expanded keys
                "view_job_financials", "create_jobs", "self_assign_ready_jobs", "self_assign_contact_jobs",
                "view_all_jobs", "view_job_reports", "approve_time_off", "approve_orders",
                "view_spending", "view_audit_log",
                "manage_flex_pool", "self_assign_flex",
                "companion_vote_power", "vote_veto",
                // Wishlist management
                "wishlist.approve", "wishlist.dismiss", "wishlist.send_to_procurement", "wishlist.reopen",
                "wishlist.auto_approve",
                // Forecasting / recommendation pipeline
                "forecasting.approve_recommendation", "forecasting.dismiss_recommendation",
                // Notebook work classification audit controls
                "notebooks.classify_todo", "notebooks.reclassify_todo", "notebooks.review_classification",
            ],
            "Manager": [
                "view_parts_catalog", "edit_parts_catalog", "edit_pricing", "show_dollar_values",
                "manage_deprecation", "view_warehouse", "manage_warehouse", "move_stock_warehouse",
                "view_trucks", "manage_trucks", "move_stock_truck", "view_jobs", "manage_jobs",
                "clock_in_out", "consume_parts_any_job", "view_labor", "manage_labor",
                "view_orders", "manage_orders", "approve_returns", "view_people", "manage_people",
                "view_reports", "export_reports", "manage_templates", "manage_notebooks", "perform_audit",
                "manager_override", "view_activity_log",
                "view_fleet", "manage_fleet", "log_fleet", "view_tools", "manage_tools",
                "view_scheduling", "manage_scheduling", "manage_dispatch",
                "view_schedule", "manage_schedule", "dispatch_employees",
                "use_chat", "view_chat", "manage_chat", "ask_qa", "send_rfi",
                "view_customers", "view_contractors",
                // 39A expanded keys
                "view_job_financials", "create_jobs", "self_assign_ready_jobs", "self_assign_contact_jobs",
                "view_all_jobs", "view_job_reports", "approve_time_off", "approve_orders",
                "view_spending",
                "manage_flex_pool", "self_assign_flex",
                "companion_vote_power",
                // Wishlist management
                "wishlist.approve", "wishlist.dismiss", "wishlist.send_to_procurement", "wishlist.reopen",
                "wishlist.auto_approve",
                // Forecasting / recommendation pipeline
                "forecasting.approve_recommendation", "forecasting.dismiss_recommendation",
                // Notebook work classification audit controls
                "notebooks.classify_todo", "notebooks.reclassify_todo", "notebooks.review_classification",
            ],
            "Office": [
                "view_parts_catalog", "edit_parts_catalog", "show_dollar_values",
                "view_warehouse", "view_trucks", "view_jobs", "manage_jobs",
                "view_labor", "manage_labor", "view_orders", "manage_orders",
                "view_people", "view_reports", "export_reports",
                "view_scheduling", "manage_scheduling", "view_schedule", "dispatch_employees",
                "use_chat", "view_chat", "ask_qa",
                "view_customers", "view_contractors",
                // 39A expanded keys
                "view_job_financials", "create_jobs", "view_all_jobs", "view_job_reports",
                "approve_time_off", "approve_orders", "view_spending",
            ],
            "Lead": [
                "view_parts_catalog", "view_warehouse", "view_trucks", "move_stock_truck",
                "view_jobs", "manage_jobs", "clock_in_out", "consume_parts_any_job",
                "view_labor", "view_orders", "view_reports",
                "view_fleet", "log_fleet", "view_tools", "view_scheduling", "view_schedule",
                "use_chat", "view_chat", "ask_qa",
                "view_customers",
                // 39A expanded keys
                "create_jobs", "self_assign_ready_jobs", "view_all_jobs",
                "view_job_reports", "manage_warehouse",
                "self_assign_flex",
                "companion_vote_power",
                // Notebook work classification submission
                "notebooks.classify_todo",
            ],
            "Worker": [
                "view_parts_catalog", "view_warehouse", "view_trucks", "move_stock_truck",
                "view_jobs", "clock_in_out", "view_labor", "view_orders",
                "view_fleet", "log_fleet", "view_tools", "view_schedule",
                "use_chat", "view_chat",
                // 39A expanded keys
                "self_assign_ready_jobs", "self_assign_contact_jobs",
                "self_assign_flex",
                // Notebook work classification submission
                "notebooks.classify_todo",
            ],
            "Apprentice": [
                "view_parts_catalog", "view_trucks", "view_jobs", "clock_in_out", "view_labor",
            ],
            "Grunt": [
                "view_parts_catalog", "view_trucks", "view_jobs", "clock_in_out",
            ],
        ]
    }
}
