import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DeviceResetService Tests")
struct DeviceResetServiceTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    /// Seed a minimal admin user so the DB has at least one user.
    /// Returns the user's ID.
    @discardableResult
    private func seedAdmin(db: AppDatabase, pin: String = "1234") throws -> Int64 {
        let auth = AuthService(db: db)
        let result = try auth.seedFirstAdmin(displayName: "TestAdmin", pin: pin)
        return result.user!.id!
    }

    // MARK: - Device Identity

    @Test("getCurrentDeviceId returns nil when no device_id setting exists")
    func testNoDeviceId() throws {
        let db = try freshDB()
        let service = DeviceResetService(db: db)
        let deviceId = try service.getCurrentDeviceId()
        #expect(deviceId == nil)
    }

    @Test("getCurrentDeviceId returns stored device_id from settings")
    func testGetDeviceId() throws {
        let db = try freshDB()
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('device_id', 'test-device-123', 'sync', datetime('now'))"
            )
        }
        let service = DeviceResetService(db: db)
        let deviceId = try service.getCurrentDeviceId()
        #expect(deviceId == "test-device-123")
    }

    // MARK: - Registered Devices

    @Test("getRegisteredDevices returns empty when no devices exist")
    func testNoRegisteredDevices() throws {
        let db = try freshDB()
        let service = DeviceResetService(db: db)
        let devices = try service.getRegisteredDevices()
        #expect(devices.isEmpty)
    }

    @Test("getRegisteredDevices returns registered devices")
    func testGetRegisteredDevices() throws {
        let db = try freshDB()
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('dev-1', 'iPad', 'ios', 'field', 1, 0, datetime('now'))
                    """
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('dev-2', 'Mac', 'macos', 'shop', 1, 0, datetime('now'))
                    """
            )
        }
        let service = DeviceResetService(db: db)
        let devices = try service.getRegisteredDevices()
        #expect(devices.count == 2)
    }

    // MARK: - Active Peers

    @Test("hasOtherActiveDevices returns false when no devices exist")
    func testNoActivePeers() throws {
        let db = try freshDB()
        let service = DeviceResetService(db: db)
        let hasPeers = try service.hasOtherActiveDevices()
        #expect(!hasPeers)
    }

    @Test("hasOtherActiveDevices returns true when other active devices exist")
    func testHasActivePeers() throws {
        let db = try freshDB()
        try db.writer.write { dbConnection in
            // Register current device
            try dbConnection.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('device_id', 'self', 'sync', datetime('now'))"
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('self', 'This Mac', 'macos', 'shop', 1, 0, datetime('now'))
                    """
            )
            // Register another active device
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('other', 'iPad', 'ios', 'field', 1, 0, datetime('now'))
                    """
            )
        }
        let service = DeviceResetService(db: db)
        let hasPeers = try service.hasOtherActiveDevices()
        #expect(hasPeers)
    }

    @Test("hasOtherActiveDevices returns false when only deactivated devices exist")
    func testOnlyDeactivatedPeers() throws {
        let db = try freshDB()
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('device_id', 'self', 'sync', datetime('now'))"
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('self', 'This Mac', 'macos', 'shop', 1, 0, datetime('now'))
                    """
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('old', 'Old iPad', 'ios', 'field', 1, 1, datetime('now'))
                    """
            )
        }
        let service = DeviceResetService(db: db)
        let hasPeers = try service.hasOtherActiveDevices()
        #expect(!hasPeers)
    }

    // MARK: - Deactivation

    @Test("deactivateCurrentDevice marks device as deactivated in registry")
    func testDeactivateDevice() throws {
        let db = try freshDB()
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('device_id', 'my-dev', 'sync', datetime('now'))"
            )
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, role, is_trusted, is_deactivated, last_seen_at)
                    VALUES ('my-dev', 'My Mac', 'macos', 'shop', 1, 0, datetime('now'))
                    """
            )
        }

        let service = DeviceResetService(db: db)
        try service.deactivateCurrentDevice()

        // Verify deactivated
        let isDeactivated: Int = try db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT is_deactivated FROM _device_registry WHERE device_id = 'my-dev'"
            )!
        }
        #expect(isDeactivated == 1)

        // Verify change log entry was created
        let changeCount: Int = try db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT COUNT(*) FROM _change_log WHERE table_name = '_device_registry' AND record_id = 'my-dev'"
            )!
        }
        #expect(changeCount == 1)
    }

    @Test("deactivateCurrentDevice does nothing when no device_id setting")
    func testDeactivateNoDevice() throws {
        let db = try freshDB()
        let service = DeviceResetService(db: db)
        // Should not throw
        try service.deactivateCurrentDevice()
    }

    // MARK: - File Deletion

    @Test("deleteDatabaseFile removes SQLite file and companions")
    func testDeleteDatabaseFile() throws {
        let tmpDir = NSTemporaryDirectory()
        let basePath = (tmpDir as NSString).appendingPathComponent("test-reset-\(UUID().uuidString).sqlite")

        // Create main file + WAL + SHM
        let fm = FileManager.default
        fm.createFile(atPath: basePath, contents: Data("db".utf8))
        fm.createFile(atPath: basePath + "-wal", contents: Data("wal".utf8))
        fm.createFile(atPath: basePath + "-shm", contents: Data("shm".utf8))

        #expect(fm.fileExists(atPath: basePath))
        #expect(fm.fileExists(atPath: basePath + "-wal"))
        #expect(fm.fileExists(atPath: basePath + "-shm"))

        try DeviceResetService.deleteDatabaseFile(atPath: basePath)

        #expect(!fm.fileExists(atPath: basePath))
        #expect(!fm.fileExists(atPath: basePath + "-wal"))
        #expect(!fm.fileExists(atPath: basePath + "-shm"))
    }

    @Test("deleteDatabaseFile does not throw when files don't exist")
    func testDeleteNonexistentFile() throws {
        let path = NSTemporaryDirectory() + "nonexistent-\(UUID().uuidString).sqlite"
        // Should not throw
        try DeviceResetService.deleteDatabaseFile(atPath: path)
    }

    // MARK: - Admin Verification

    @Test("verifyAdminApproval returns true for admin user with correct PIN")
    func testAdminApprovalSuccess() throws {
        let db = try freshDB()
        let userId = try seedAdmin(db: db, pin: "5678")
        let service = DeviceResetService(db: db)
        let approved = try service.verifyAdminApproval(userId: userId, pin: "5678")
        #expect(approved)
    }

    @Test("verifyAdminApproval returns false for wrong PIN")
    func testAdminApprovalWrongPin() throws {
        let db = try freshDB()
        let userId = try seedAdmin(db: db, pin: "5678")
        let service = DeviceResetService(db: db)
        let approved = try service.verifyAdminApproval(userId: userId, pin: "0000")
        #expect(!approved)
    }

    @Test("getAdminUsers returns users with manage_devices permission")
    func testGetAdminUsers() throws {
        let db = try freshDB()
        try seedAdmin(db: db)
        let service = DeviceResetService(db: db)
        let admins = try service.getAdminUsers()
        #expect(!admins.isEmpty)
        #expect(admins.first?.displayName == "TestAdmin")
    }

    @Test("getAdminUsers returns empty when no users exist")
    func testGetAdminUsersEmpty() throws {
        let db = try freshDB()
        let service = DeviceResetService(db: db)
        let admins = try service.getAdminUsers()
        #expect(admins.isEmpty)
    }
}
