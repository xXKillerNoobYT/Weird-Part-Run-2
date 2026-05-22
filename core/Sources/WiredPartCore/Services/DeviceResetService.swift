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
        do {
            return try db.writer.read { dbConnection in
                try String.fetchOne(
                    dbConnection,
                    sql: "SELECT value FROM settings WHERE key = 'device_id'"
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Get all devices registered in the local device registry.
    public func getRegisteredDevices() throws -> [RegisteredDevice] {
        do {
            return try db.writer.read { dbConnection in
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
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Check whether there are other active (non-deactivated) devices in the registry.
    public func hasOtherActiveDevices() throws -> Bool {
        let currentId = try getCurrentDeviceId()
        do {
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
        } catch {
            if isTableNotFoundError(error) { return false }
            throw error
        }
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

            // Log this change so it syncs to peers.
            // Fix #181: _change_log.record_id is INTEGER but _device_registry's primary key
            // is the text device_id UUID. We use 0 for record_id and include the actual
            // device_id in changed_fields JSON so peers can identify the affected row.
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

    /// Delete all database-owned local files, including local database backups.
    /// Reset is a full local wipe, so leaving backup snapshots behind preserves
    /// recoverable user data after the app returns to first-run setup.
    public static func deleteDatabaseStorage(atPath path: String) throws {
        try deleteDatabaseFile(atPath: path)

        let fm = FileManager.default
        let backupPath = (path as NSString).deletingLastPathComponent + "/Backups"
        if fm.fileExists(atPath: backupPath) {
            try fm.removeItem(atPath: backupPath)
        }
    }

    /// Clear app-scoped defaults that survive SQLite deletion.
    /// Passing a custom suite makes the behavior testable without touching
    /// process-wide defaults.
    public static func clearSavedAppState(
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier
    ) {
        if let domainName {
            defaults.removePersistentDomain(forName: domainName)
        }
        defaults.synchronize()
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
        do {
            return try db.writer.read { dbConnection in
                try User.fetchAll(
                    dbConnection,
                    sql: """
                        SELECT DISTINCT u.* FROM users u
                        JOIN user_hats uh ON uh.user_id = u.id AND uh.deleted_at IS NULL
                        JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                        WHERE u.is_active = 1
                          AND u.deleted_at IS NULL
                          AND uh.is_active = 1
                          AND hp.permission_key = 'manage_devices'
                        ORDER BY u.display_name ASC
                        """
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Helpers

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
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
