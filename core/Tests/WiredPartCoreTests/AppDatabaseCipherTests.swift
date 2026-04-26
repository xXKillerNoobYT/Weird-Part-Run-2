import Foundation
import Testing
import GRDB
import CryptoKit
@testable import WiredPartCore

// MARK: - AppDatabaseCipherTests

/// Unit tests for SQLCipher whole-database encryption.
///
/// These tests validate:
///  1. Key derivation is deterministic (same PIN + salt → same hex key).
///  2. Key derivation is sensitive to PIN and salt changes.
///  3. Plaintext-to-encrypted migration roundtrip preserves all rows.
///  4. Migration rolls back (original preserved) on export failure.
///  5. (Salt persistence across "sessions" is covered by `testSaltLoadOrCreate`.)
///
/// Tests use temporary files in the system temp directory.
/// Keychain I/O in `CipherKeyManager.loadOrCreateSalt()` is tested separately via the
/// `testSaltLoadOrCreate` helper which exercises the real Keychain API on macOS/iOS.
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
            try? fm.removeItem(atPath: p)
            try? fm.removeItem(atPath: p + "-wal")
            try? fm.removeItem(atPath: p + "-shm")
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
        // Use shared CipherKeyManager — on a real device / simulator the Keychain is available.
        // This test verifies the salt is always 32 bytes and stable across two calls.
        let manager = CipherKeyManager.shared
        let salt1 = try manager.loadOrCreateSalt()
        let salt2 = try manager.loadOrCreateSalt()
        #expect(salt1.count == 32)
        #expect(salt1 == salt2)  // idempotent — same salt on second call
    }

    // MARK: - Migration Roundtrip

    @Test("testPlaintextToEncryptedMigrationRoundtrip — all rows readable after migration")
    func testPlaintextToEncryptedMigrationRoundtrip() throws {
        let path = tmpPath("migrate")
        defer { cleanup(path) }

        // 1. Create a plaintext DB with a known row.
        // Use file-based plaintext DB for the migration test.
        let plainPool = try DatabasePool(path: path)
        try plainPool.write { db in
            // Create a minimal table and insert a sentinel row.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS _test_cipher (id INTEGER PRIMARY KEY, value TEXT)
            """)
            try db.execute(sql: "INSERT INTO _test_cipher (value) VALUES ('hello encrypted world')")
        }
        // Close the plaintext pool.
        try plainPool.close()

        // 2. Run migration.
        let salt = Data(repeating: 0xAA, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "9876", salt: salt)
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        // 3. Open encrypted DB and verify row is present.
        let encPool = try AppDatabase.makeEncryptedPool(path: path, keyHex: keyHex)
        let value: String? = try encPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT value FROM _test_cipher LIMIT 1")
            return row?["value"]
        }
        try encPool.close()

        #expect(value == "hello encrypted world")
    }

    @Test("testMigrationIsIdempotent — calling migrate twice does not corrupt DB")
    func testMigrationIsIdempotent() throws {
        let path = tmpPath("idem")
        defer { cleanup(path) }

        // Seed a plaintext DB.
        let plainPool = try DatabasePool(path: path)
        try plainPool.write { db in
            try db.execute(sql: "CREATE TABLE _t (n INTEGER PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO _t (n) VALUES (42)")
        }
        try plainPool.close()

        let salt = Data(repeating: 0xBB, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "4321", salt: salt)

        // First migration.
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)
        // Second call — should be a no-op (file already encrypted).
        try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)

        let encPool = try AppDatabase.makeEncryptedPool(path: path, keyHex: keyHex)
        let n: Int? = try encPool.read { db in
            try Int.fetchOne(db, sql: "SELECT n FROM _t LIMIT 1")
        }
        try encPool.close()

        #expect(n == 42)
    }

    @Test("testMigrationRollbackOnFailure — original DB preserved when temp path is unwritable")
    func testMigrationRollbackOnFailure() throws {
        // We simulate failure by using a path whose parent directory doesn't exist, so
        // the ATTACH for the temp file fails.  The original DB must remain intact.
        let parentDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("WPCipherTest_NoSuchDir_\(UUID().uuidString)")
        let path = (parentDir as NSString).appendingPathComponent("db.sqlite")
        let fm = FileManager.default

        // Create the directory, seed plaintext DB, then remove the directory so ATTACH fails.
        try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: path)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE _r (v TEXT)")
            try db.execute(sql: "INSERT INTO _r (v) VALUES ('original')")
        }
        try pool.close()

        // Read original content for comparison.
        let originalPool = try DatabasePool(path: path)
        let originalValue: String? = try originalPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT v FROM _r LIMIT 1")
            return row?["v"]
        }
        try originalPool.close()

        // Simulate migration failure by removing write permission on the parent directory.
        // This makes the temp file (db.sqlite.encrypted.tmp) unwritable so ATTACH fails.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parentDir)
        defer {
            // Restore so cleanup works.
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parentDir)
            try? fm.removeItem(atPath: parentDir)
        }

        let salt = Data(repeating: 0xCC, count: 32)
        let keyHex = CipherKeyManager.deriveKey(pin: "0000", salt: salt)

        // Migration MUST fail (temp path is not writable).
        var didThrow = false
        do {
            try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected migration to throw when temp path is unwritable")

        // Restore permissions and verify original DB is intact.
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parentDir)
        let checkPool = try DatabasePool(path: path)
        let checkValue: String? = try checkPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT v FROM _r LIMIT 1")
            return row?["v"]
        }
        try checkPool.close()

        #expect(checkValue == originalValue, "Original plaintext DB must be unmodified after migration failure")
    }
}
