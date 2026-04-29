import Foundation
import Testing
import GRDB
import CryptoKit
@testable import WiredPartCore

// MARK: - AppDatabaseCipherTests

/// Unit tests for SQLCipher whole-database encryption.
///
/// Covers:
///  - Key derivation determinism and sensitivity (PIN / salt).
///  - Salt persistence (Keychain idempotency).
///  - Option B migration: fresh install skip, empty DB, populated DB with row-count
///    verification, idempotency, and failure-rollback guarantees.
@Suite("AppDatabase Cipher Tests", .serialized)
struct AppDatabaseCipherTests {

    // MARK: - Helpers

    private func tmpPath(_ name: String) -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("WPCipherTest_\(name)_\(UUID().uuidString).sqlite")
    }

    private func cleanup(_ paths: String...) {
        let fm = FileManager.default
        for p in paths {
            for suffix in ["", "-wal", "-shm", ".encrypted-tmp", ".encrypted-tmp-wal",
                           ".encrypted-tmp-shm", ".unencrypted.bak"] {
                try? fm.removeItem(atPath: p + suffix)
            }
        }
    }

    // MARK: - Key Derivation

    @Test("testKeyDerivationDeterministic — same PIN + salt yields identical hex key")
    func testKeyDerivationDeterministic() {
        let salt = Data([0x01, 0x02, 0x03, 0x04] + Array(repeating: 0xAB, count: 28))
        let key1 = CipherKeyManager.deriveKey(pin: "1234", salt: salt)
        let key2 = CipherKeyManager.deriveKey(pin: "1234", salt: salt)
        #expect(key1 == key2)
        #expect(key1.count == 64)  // SHA-256 = 32 bytes = 64 hex chars
        #expect(key1.allSatisfy { $0.isHexDigit })
    }

    @Test("testKeyDerivationSensitiveToPIN — different PINs produce different keys")
    func testKeyDerivationSensitiveToPIN() {
        let salt = Data(repeating: 0xFF, count: 32)
        let key1 = CipherKeyManager.deriveKey(pin: "1234", salt: salt)
        let key2 = CipherKeyManager.deriveKey(pin: "5678", salt: salt)
        #expect(key1 != key2)
    }

    @Test("testKeyDerivationSensitiveToSalt — different salts produce different keys")
    func testKeyDerivationSensitiveToSalt() {
        let salt1 = Data(repeating: 0x00, count: 32)
        let salt2 = Data(repeating: 0xFF, count: 32)
        let key1 = CipherKeyManager.deriveKey(pin: "1234", salt: salt1)
        let key2 = CipherKeyManager.deriveKey(pin: "1234", salt: salt2)
        #expect(key1 != key2)
    }

    @Test("testSaltLoadOrCreate — generates 32-byte salt and is idempotent")
    func testSaltLoadOrCreate() throws {
        let manager = CipherKeyManager.shared
        let salt1 = try manager.loadOrCreateSalt()
        let salt2 = try manager.loadOrCreateSalt()
        #expect(salt1.count == 32)
        #expect(salt1 == salt2)  // idempotent — same salt on second call
    }

    // MARK: - Option B Migration Tests

    @Test("testFreshInstallNoUnencryptedDBSkipsMigration — non-existent path is a no-op")
    func testFreshInstallNoUnencryptedDBSkipsMigration() throws {
        let path = tmpPath("fresh")
        defer { cleanup(path) }

        let salt = Data(repeating: 0x11, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "0000", salt: salt)

        // Must not throw and must not create any file.
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        #expect(!FileManager.default.fileExists(atPath: path),
                "No file should be created for a fresh-install path")
    }

    @Test("testEmptyUnencryptedDBMigratesSuccessfully — schema-only plaintext DB opens encrypted")
    func testEmptyUnencryptedDBMigratesSuccessfully() throws {
        let path = tmpPath("empty")
        defer { cleanup(path) }

        // Create a full-schema plaintext AppDatabase (all migrations, no user rows).
        let plainDB = try AppDatabase.openDatabase(atPath: path)
        _ = plainDB  // ensure migrator ran
        // Close the database writer before migration.
        try (plainDB.writer as? DatabasePool)?.close()

        let salt = Data(repeating: 0x22, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "1111", salt: salt)

        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        // Must open as encrypted without error.
        let encDB = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
        let version: String? = try encDB.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'db_schema_version'")
        }
        #expect(version == "\(AppDatabase.schemaVersion)",
                "Schema version should match after migration of empty DB")
    }

    @Test("testPopulatedUnencryptedDBMigratesAllTablesWithRowCountVerification — user data preserved")
    func testPopulatedUnencryptedDBMigratesAllTablesWithRowCountVerification() throws {
        let path = tmpPath("populated")
        defer { cleanup(path) }

        // 1. Create a full-schema plaintext AppDatabase and insert test rows into two tables.
        let plainDB = try AppDatabase.openDatabase(atPath: path)
        // Insert a custom settings entry (no FK dependency).
        try plainDB.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value, category)
                VALUES ('cipher_migration_test', 'hello_option_b', 'test')
            """)
        }
        // Insert a part_category (no FK dependency).
        try plainDB.writer.write { db in
            try db.execute(sql: """
                INSERT INTO part_categories (name, icon, color, description)
                VALUES ('MigrationTestCat', '⚙️', '#FF0000', 'cipher test row')
            """)
        }
        let plainSettingsCount = try plainDB.writer.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")) ?? 0
        }
        let plainCatCount = try plainDB.writer.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM part_categories")) ?? 0
        }
        try (plainDB.writer as? DatabasePool)?.close()

        // 2. Migrate to encrypted.
        let salt = Data(repeating: 0x33, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "2222", salt: salt)
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        // 3. Verify data is present in the encrypted DB.
        let encDB = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
        let testValue: String? = try encDB.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'cipher_migration_test'")
        }
        let encSettingsCount = try encDB.writer.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")) ?? 0
        }
        let encCatCount = try encDB.writer.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM part_categories")) ?? 0
        }

        #expect(testValue == "hello_option_b", "Custom settings row must survive migration")
        #expect(encSettingsCount == plainSettingsCount, "settings row count must match")
        #expect(encCatCount == plainCatCount, "part_categories row count must match")
    }

    @Test("testIdempotencyAlreadyEncryptedSkipsMigration — second call is a no-op")
    func testIdempotencyAlreadyEncryptedSkipsMigration() throws {
        let path = tmpPath("idempotent")
        defer { cleanup(path) }

        // 1. Create a full-schema plaintext DB and migrate to encrypted.
        let plainDB = try AppDatabase.openDatabase(atPath: path)
        try plainDB.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value, category)
                VALUES ('idempotency_test', 'still_here', 'test')
            """)
        }
        try (plainDB.writer as? DatabasePool)?.close()

        let salt = Data(repeating: 0x44, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "3333", salt: salt)

        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        // 2. Call a second time — must be a no-op (DB is already encrypted).
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        // 3. Verify the encrypted DB still works and data is intact.
        let encDB = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)
        let value: String? = try encDB.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'idempotency_test'")
        }
        #expect(value == "still_here", "Data must be intact after idempotent second migration call")
    }

    @Test("testFailureMidImportLeavesOriginalDBIntact — original plaintext DB preserved on error")
    func testFailureMidImportLeavesOriginalDBIntact() throws {
        // Simulate a migration failure by making the parent directory read-only so the
        // encrypted temp file cannot be created. The original plaintext DB must remain
        // untouched and still be readable as a plaintext SQLite file.
        let parentDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("WPCipherTest_Rollback_\(UUID().uuidString)")
        let path = (parentDir as NSString).appendingPathComponent("db.sqlite")
        let fm = FileManager.default

        try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parentDir)
            try? fm.removeItem(atPath: parentDir)
        }

        // Seed a full-schema plaintext DB with a sentinel row.
        let plainDB = try AppDatabase.openDatabase(atPath: path)
        try plainDB.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value, category)
                VALUES ('rollback_sentinel', 'original_value', 'test')
            """)
        }
        try (plainDB.writer as? DatabasePool)?.close()

        // Record original settings row count for comparison.
        let origPool = try DatabasePool(path: path)
        let origCount = try origPool.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")) ?? 0
        }
        try origPool.close()

        // Make the directory non-writable so creating the encrypted temp file fails.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parentDir)

        let salt = Data(repeating: 0x55, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "4444", salt: salt)

        var didThrow = false
        do {
            try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Migration must throw when the temp path is unwritable")

        // Restore permissions and verify the original plaintext DB is intact.
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parentDir)

        let checkPool = try DatabasePool(path: path)
        let checkCount = try checkPool.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings")) ?? 0
        }
        let sentinel: String? = try checkPool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'rollback_sentinel'")
        }
        try checkPool.close()

        #expect(checkCount == origCount, "Row count must be unchanged after failed migration")
        #expect(sentinel == "original_value", "Sentinel row must be intact in original DB")
    }
}
