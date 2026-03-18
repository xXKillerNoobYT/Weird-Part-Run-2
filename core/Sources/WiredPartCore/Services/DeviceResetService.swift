import Foundation
import GRDB

/// Manages database reset and device deactivation lifecycle.
///
/// Reset flow:
/// 1. Mark this device as deactivated in `_device_registry`
/// 2. If peers are available, push deactivation so they know
/// 3. Close all DB connections
/// 4. Delete the SQLite file (+ WAL + SHM)
/// 5. App re-initializes with a fresh database → bootstrap screen
///
/// Any authenticated user can initiate a reset request, but an Admin
/// (with `manage_devices` permission) must approve it by entering their PIN.
public final class DeviceResetService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Device Identity

    /// Get the current device's ID from the settings table.
    /// The device ID is stored as a setting with key "device_id" during sync setup.
    public func getCurrentDeviceId() throws -> String? {
        try db.writer.read { dbConnection in
            try String.fetchOne(
                dbConnection,
                sql: "SELECT value FROM settings WHERE key = 'device_id'"
            )
        }
    }

    /// Get all devices registered in the local device registry.
    public func getRegisteredDevices() throws -> [RegisteredDevice] {
        try db.writer.read { dbConnection in
            try RegisteredDevice.fetchAll(
                dbConnection,
                sql: """
                    SELECT device_id, device_name, platform, role,
                           last_seen_at, last_sync_at, is_trusted, is_deactivated
                    FROM _device_registry
                    ORDER BY last_seen_at DESC
                    """
            )
        }
    }

    /// Check whether there are other active (non-deactivated) devices in the registry.
    public func hasOtherActiveDevices() throws -> Bool {
        let currentId = try getCurrentDeviceId()
        let count: Int = try db.writer.read { dbConnection in
            if let currentId {
                return try Int.fetchOne(
                    dbConnection,
                    sql: """
                        SELECT COUNT(*) FROM _device_registry
                        WHERE is_deactivated = 0 AND device_id != ?
                        """,
                    arguments: [currentId]
                ) ?? 0
            } else {
                return try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM _device_registry WHERE is_deactivated = 0"
                ) ?? 0
            }
        }
        return count > 0
    }

    // MARK: - Deactivation

    /// Mark the current device as deactivated in the local `_device_registry`.
    /// This change will be picked up by sync and propagated to peers.
    public func deactivateCurrentDevice() throws {
        guard let deviceId = try getCurrentDeviceId() else { return }

        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    UPDATE _device_registry
                    SET is_deactivated = 1
                    WHERE device_id = ?
                    """,
                arguments: [deviceId]
            )

            // Also log this in the change log so it syncs to peers
            try dbConnection.execute(
                sql: """
                    INSERT INTO _change_log
                        (table_name, record_id, operation, device_id, changed_fields, timestamp)
                    VALUES ('_device_registry', ?, 'UPDATE', ?, '["is_deactivated"]', datetime('now'))
                    """,
                arguments: [deviceId, deviceId]
            )
        }
    }

    /// Push pending changes (including our deactivation) to connected peers.
    /// Returns the number of peers that were successfully notified.
    public func pushDeactivationToPeers(peerManager: PeerManager) async -> Int {
        // Trigger a sync cycle so the deactivation change is pushed to all peers
        let results = await peerManager.syncWithAllPeers()
        return results.filter { $0.success }.count
    }

    // MARK: - File Deletion

    /// Delete the SQLite database file and its WAL/SHM companions.
    /// This is a static method so it can be called after the DB connection is closed.
    public static func deleteDatabaseFile(atPath path: String) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let filePath = path + suffix
            if fm.fileExists(atPath: filePath) {
                try fm.removeItem(atPath: filePath)
            }
        }
    }

    // MARK: - Admin Verification

    /// Verify that a user has admin-level permission to approve a reset.
    /// Returns true if the user has the `manage_devices` permission.
    public func verifyAdminApproval(userId: Int64, pin: String) throws -> Bool {
        let authService = AuthService(db: db)
        let result = try authService.authenticateByPin(userId: userId, pin: pin)
        guard result.success else { return false }

        let permissions = try authService.getUserPermissions(userId)
        return permissions.contains("manage_devices")
    }

    /// Get list of users who have admin permissions (for the approval picker).
    public func getAdminUsers() throws -> [User] {
        try db.writer.read { dbConnection in
            try User.fetchAll(
                dbConnection,
                sql: """
                    SELECT DISTINCT u.* FROM users u
                    JOIN user_hats uh ON uh.user_id = u.id
                    JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                    WHERE u.is_active = 1
                      AND uh.is_active = 1
                      AND hp.permission_key = 'manage_devices'
                    ORDER BY u.display_name ASC
                    """
            )
        }
    }
}

// MARK: - Registered Device Model

/// Lightweight model for displaying devices in the reset UI.
public struct RegisteredDevice: Codable, FetchableRecord, Sendable {
    public let deviceId: String
    public let deviceName: String?
    public let platform: String?
    public let role: String?
    public let lastSeenAt: String?
    public let lastSyncAt: String?
    public let isTrusted: Int
    public let isDeactivated: Int

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case role
        case lastSeenAt = "last_seen_at"
        case lastSyncAt = "last_sync_at"
        case isTrusted = "is_trusted"
        case isDeactivated = "is_deactivated"
    }
}
