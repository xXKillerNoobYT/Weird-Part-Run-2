import Foundation
import CryptoKit
import GRDB

/// Local Auth Service — PIN authentication + first-run bootstrap.
///
/// Every device authenticates against its own local SQLite DB.
/// User records come from either:
///   1. `seedFirstAdmin()` — the very first device in a new company
///   2. Sync from another device — all subsequent devices
///
/// PIN verification uses SHA-256 hashes stored locally. Session tokens
/// are base64-encoded JSON payloads (24-hour expiry).
///
/// Ported from: `src/local/services/auth-service.ts`
public final class AuthService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Types

    /// Result of an authentication attempt.
    public struct AuthResult: Sendable {
        public let success: Bool
        public let user: User?
        public let token: String?
        public let message: String
    }

    /// Decoded session token payload.
    public struct TokenPayload: Codable, Sendable {
        public let sub: Int64
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

    // MARK: - Authentication

    /// Authenticate a user by PIN against the local database.
    public func authenticateByPin(userId: Int64, pin: String) throws -> AuthResult {
        let user: User? = try db.writer.read { dbConnection in
            try User.fetchOne(
                dbConnection,
                sql: "SELECT * FROM users WHERE id = ? AND is_active = 1",
                arguments: [userId]
            )
        }

        guard let user else {
            return AuthResult(success: false, user: nil, token: nil, message: "User not found or inactive")
        }

        guard let pinHash = user.pinHash, pinHash != "__PLACEHOLDER_HASH__" else {
            return AuthResult(success: false, user: nil, token: nil, message: "PIN not configured. Sync with shop first.")
        }

        let isValid = Self.verifyPinLocally(pin: pin, storedHash: pinHash, salt: user.pinSalt)
        guard isValid else {
            return AuthResult(success: false, user: nil, token: nil, message: "Invalid PIN")
        }

        guard let userId = user.id else {
            return AuthResult(success: false, user: nil, token: nil, message: "User record missing ID")
        }

        // Migration path: re-hash legacy PINs with a per-user salt on successful login
        if user.pinSalt == nil {
            let newSalt = Self.generateSalt()
            let newHash = Self.hashPin(pin, salt: newSalt)
            let now = Self.currentTimestamp()
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: "UPDATE users SET pin_hash = ?, pin_salt = ?, updated_at = ? WHERE id = ?",
                    arguments: [newHash, newSalt, now, userId]
                )
            }
        }

        let token = Self.generateLocalToken(userId: userId)
        return AuthResult(success: true, user: user, token: token, message: "Authenticated")
    }

    /// Get list of active users for the login screen.
    public func getActiveUsers() throws -> [User] {
        try db.writer.read { dbConnection in
            try User.fetchAll(
                dbConnection,
                sql: "SELECT * FROM users WHERE is_active = 1 ORDER BY display_name ASC"
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
            return AuthResult(success: false, user: nil, token: nil, message: "Users already exist. Seed aborted.")
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
            return AuthResult(success: false, user: nil, token: nil, message: "Failed to create admin user")
        }

        let token = Self.generateLocalToken(userId: userId)
        return AuthResult(success: true, user: user, token: token, message: "Company database initialized. Welcome!")
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
    public func getUserPermissions(_ userId: Int64) throws -> [String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: """
                    SELECT DISTINCT hp.permission_key
                    FROM user_hats uh
                    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                    WHERE uh.user_id = ? AND uh.is_active = 1
                    """,
                arguments: [userId]
            )
            return rows.compactMap { $0["permission_key"] as? String }
        }
    }

    /// Check if user has a specific permission.
    public func hasPermission(_ userId: Int64, permissionKey: String) throws -> Bool {
        try db.writer.read { dbConnection in
            let count = try Int.fetchOne(
                dbConnection,
                sql: """
                    SELECT COUNT(*) FROM user_hats uh
                    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                    WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = ?
                    LIMIT 1
                    """,
                arguments: [userId, permissionKey]
            ) ?? 0
            return count > 0
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
        try db.writer.write { dbConnection in
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
                    WHERE uh.user_id = ? AND uh.is_active = 1
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
                    WHERE uh.user_id = ? AND uh.is_active = 1
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
        guard let payload = Self.parseLocalToken(token) else {
            throw AuthError.invalidToken
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        guard payload.exp > nowMs else {
            throw AuthError.tokenExpired
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

    public enum AuthError: Error, Sendable {
        case invalidToken
        case tokenExpired
        case userNotFound
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
                    LEFT JOIN users u ON u.id = d.assigned_user_id
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
                        userId: "\(row["device_id"] as Int64? ?? 0)",
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

    /// Force-deactivate a session by its rowid in the device registry.
    public func deactivateSession(sessionId: String) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE rowid = ?",
                arguments: [sessionId]
            )
        }
    }

    /// Check if a last_seen timestamp is within the last 5 minutes.
    private static func isRecentlyOnline(_ lastSeen: String?) -> Bool {
        guard let lastSeen, !lastSeen.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: lastSeen) {
            return Date().timeIntervalSince(date) < 300
        }
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = simple.date(from: lastSeen) {
            return Date().timeIntervalSince(date) < 300
        }
        return false
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

    // MARK: - Internal Helpers

    /// Verify a PIN against a stored hash.
    /// Supports both legacy (fixed salt) and new (per-user salt + key stretching) formats.
    static func verifyPinLocally(pin: String, storedHash: String, salt: String?) -> Bool {
        // If it's a bcrypt hash, we can't verify offline
        if storedHash.hasPrefix("$2b$") || storedHash.hasPrefix("$2a$") {
            return false
        }

        if let salt {
            // New per-user salted hash with key stretching
            let computed = hashPin(pin, salt: salt)
            return computed == storedHash
        } else {
            // Legacy fixed-salt hash (pre-migration 023)
            let computed = legacyHashPin(pin)
            return computed == storedHash
        }
    }

    /// Hash a PIN with a per-user salt using iterated SHA-256 for key stretching.
    static func hashPin(_ pin: String, salt: String) -> String {
        let input = Data((pin + ":" + salt).utf8)
        var hash = SHA256.hash(data: input)
        for _ in 0..<10_000 {
            hash = SHA256.hash(data: Data(hash))
        }
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Legacy fixed-salt hash for backward compatibility during migration.
    /// Used only to verify old PINs before re-hashing with a per-user salt.
    private static func legacyHashPin(_ pin: String) -> String {
        let data = Data((pin + ":wiredpart").utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate a random salt for PIN hashing.
    static func generateSalt() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    /// Generate a simple local session token (base64 JSON).
    /// Returns nil if encoding fails — never returns a magic string.
    static func generateLocalToken(userId: Int64) -> String? {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let payload = TokenPayload(
            sub: userId,
            iat: nowMs,
            exp: nowMs + 24 * 60 * 60 * 1000, // 24 hours
            type: "local"
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        return data.base64EncodedString()
    }

    /// Parse a local token (base64-encoded JSON). Returns nil if invalid.
    static func parseLocalToken(_ token: String) -> TokenPayload? {
        guard let data = Data(base64Encoded: token) else { return nil }
        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else { return nil }
        guard payload.type == "local" else { return nil }
        return payload
    }

    /// Current ISO-8601-ish timestamp (matching the TS format: "YYYY-MM-DD HH:MM:SS").
    private static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
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
                "view_fleet", "manage_fleet", "view_tools", "manage_tools",
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
            ],
            "Manager": [
                "view_parts_catalog", "edit_parts_catalog", "edit_pricing", "show_dollar_values",
                "manage_deprecation", "view_warehouse", "manage_warehouse", "move_stock_warehouse",
                "view_trucks", "manage_trucks", "move_stock_truck", "view_jobs", "manage_jobs",
                "clock_in_out", "consume_parts_any_job", "view_labor", "manage_labor",
                "view_orders", "manage_orders", "approve_returns", "view_people", "manage_people",
                "view_reports", "export_reports", "manage_templates", "manage_notebooks", "perform_audit",
                "manager_override", "view_activity_log",
                "view_fleet", "manage_fleet", "view_tools", "manage_tools",
                "view_scheduling", "manage_scheduling", "manage_dispatch",
                "view_schedule", "manage_schedule", "dispatch_employees",
                "use_chat", "view_chat", "manage_chat", "ask_qa", "send_rfi",
                "view_customers", "view_contractors",
                // 39A expanded keys
                "view_job_financials", "create_jobs", "self_assign_ready_jobs", "self_assign_contact_jobs",
                "view_all_jobs", "view_job_reports", "approve_time_off", "approve_orders",
                "view_spending",
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
                "view_fleet", "view_tools", "view_scheduling", "view_schedule",
                "use_chat", "view_chat", "ask_qa",
                "view_customers",
                // 39A expanded keys
                "create_jobs", "self_assign_ready_jobs", "view_all_jobs",
                "view_job_reports", "manage_warehouse",
            ],
            "Worker": [
                "view_parts_catalog", "view_warehouse", "view_trucks", "move_stock_truck",
                "view_jobs", "clock_in_out", "view_labor", "view_orders",
                "view_fleet", "view_tools", "view_schedule",
                "use_chat", "view_chat",
                // 39A expanded keys
                "self_assign_ready_jobs", "self_assign_contact_jobs",
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
