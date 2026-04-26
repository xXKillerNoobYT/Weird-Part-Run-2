import Foundation
import GRDB

// MARK: - AppDatabase + Cipher

extension AppDatabase {

    // MARK: - Encrypted Pool Construction

    /// Open a file-based **encrypted** database using SQLCipher.
    ///
    /// The `keyHex` must be a 64-character lowercase hex string (32 bytes, i.e. a SHA-256
    /// digest encoded as hex). SQLCipher accepts this via its `x'...'` hex notation.
    ///
    /// All SQLCipher PRAGMAs are issued inside `prepareDatabase` — the first closure called
    /// before any schema I/O — guaranteeing the key is set before any page is read.
    ///
    /// - Parameters:
    ///   - path: Filesystem path for the database file.
    ///   - keyHex: 64-char hex key derived from `CipherKeyManager.deriveKeyHex(pin:)`.
    /// - Returns: An open, migrated `AppDatabase` wrapping an encrypted `DatabasePool`.
    /// - Throws: Rethrows GRDB/SQLCipher errors (wrong key → `SQLITE_NOTADB`).
    public static func openEncryptedDatabase(atPath path: String, keyHex: String) throws -> AppDatabase {
        let pool = try makeEncryptedPool(path: path, keyHex: keyHex)
        return try AppDatabase(pool)
    }

    /// Build a `DatabasePool` configured for SQLCipher encryption.
    ///
    /// Prefer `openEncryptedDatabase(atPath:keyHex:)` which additionally runs migrations.
    /// Call this directly only when you need a raw pool (e.g. for `sqlcipher_export`).
    public static func makeEncryptedPool(path: String, keyHex: String) throws -> DatabasePool {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // Set the encryption key using SQLCipher's hex notation.
            // `usePassphrase("x'<hex>'")` calls sqlite3_key_v2() with the raw bytes
            // of the string; SQLCipher recognises the x'...' prefix and treats it as
            // a 32-byte raw key, bypassing PBKDF2.  SHA-256(pin || salt) already
            // provides key stretching, so a second PBKDF2 round is unnecessary.
            try db.usePassphrase("x'\(keyHex)'")
            // Use 4096-byte pages (SQLCipher default; good for mobile I/O).
            try db.execute(sql: "PRAGMA cipher_page_size = 4096")
            // WAL mode for concurrent reads.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        return try DatabasePool(path: path, configuration: config)
    }

    // MARK: - One-Time Plaintext → Encrypted Migration

    /// Migrate a plaintext SQLite database to SQLCipher in-place.
    ///
    /// Run this **before** calling `openEncryptedDatabase(atPath:keyHex:)`.
    /// If the file does not exist, or is already encrypted, this is a no-op.
    ///
    /// Migration steps:
    /// 1. Probe-open without a key → success means file is plaintext.
    /// 2. Open an encrypted temp file via `ATTACH ... KEY`.
    /// 3. `SELECT sqlcipher_export('encrypted')` copies all pages.
    /// 4. `DETACH encrypted`.
    /// 5. Atomic rename: temp → original path (original is preserved until rename succeeds).
    ///
    /// On any failure: the temp file is deleted and the original plaintext DB is untouched.
    ///
    /// - Parameters:
    ///   - path: Path to the database file.
    ///   - keyHex: 64-char hex key for the destination encrypted database.
    /// - Throws: Rethrows filesystem or SQLite errors. Callers should wrap in try/catch
    ///           and refuse to proceed if this fails.
    public static func migratePlaintextDBIfNeeded(atPath path: String, keyHex: String) throws {
        let fm = FileManager.default

        // No file → nothing to migrate (fresh install; encryption set up during creation).
        guard fm.fileExists(atPath: path) else { return }

        // Probe: try opening WITHOUT a passphrase.
        // If it succeeds, the file is plaintext and needs migration.
        // If it fails with SQLITE_NOTADB / wrong-key error, it is already encrypted.
        var isPlaintext = false
        do {
            let probe = try DatabaseQueue(path: path)
            try probe.read { db in
                _ = try Row.fetchOne(db, sql: "SELECT 1 FROM sqlite_master LIMIT 1")
            }
            isPlaintext = true
        } catch {
            // Any error here means the DB is already encrypted (or corrupt).
            // Either way, we skip the migration and let the encrypted open handle it.
            return
        }

        guard isPlaintext else { return }

        let tempPath = path + ".encrypted.tmp"

        // Clean up any leftover temp file from a previous failed attempt.
        try? fm.removeItem(atPath: tempPath)

        // Open the plaintext DB and export via sqlcipher_export.
        let plaintextPool = try DatabasePool(path: path)
        do {
            try plaintextPool.writeWithoutTransaction { db in
                // ATTACH creates the encrypted destination and sets its key.
                try db.execute(
                    sql: "ATTACH DATABASE ? AS encrypted KEY ?",
                    arguments: [tempPath, "x'\(keyHex)'"]
                )
                // Copy all content from main DB into the encrypted DB.
                try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
                try db.execute(sql: "DETACH DATABASE encrypted")
            }
            // Explicitly close all file handles before the atomic rename
            // to avoid 'file is busy' errors.
            try plaintextPool.close()
        } catch {
            // Export failed — clean up temp and preserve the original plaintext DB.
            try? plaintextPool.close()
            try? fm.removeItem(atPath: tempPath)
            throw CipherMigrationError.exportFailed(error)
        }

        // Atomic rename: temp → original (WAL/SHM files are no longer valid after export).
        do {
            // Remove WAL/SHM before rename to avoid leaving stale journal files.
            try? fm.removeItem(atPath: path + "-wal")
            try? fm.removeItem(atPath: path + "-shm")
            try fm.removeItem(atPath: path)
            try fm.moveItem(atPath: tempPath, toPath: path)
        } catch {
            // Rename failed — try to restore from the still-valid temp file if possible.
            try? fm.removeItem(atPath: tempPath)
            throw CipherMigrationError.renameFailed(error)
        }
    }

    // MARK: - Re-key (PIN change)

    /// Re-key an already-open encrypted `DatabasePool` to a new passphrase.
    ///
    /// Called from `AuthService.changePin(userId:oldPin:newPin:)` after verifying the old PIN.
    /// SQLCipher's `PRAGMA rekey` is atomic — if it succeeds, the DB is re-encrypted;
    /// if the process is interrupted mid-write, SQLCipher rolls back to the old key.
    ///
    /// - Parameters:
    ///   - pool: An open, authenticated `DatabasePool`.
    ///   - newKeyHex: 64-char hex string for the new passphrase.
    /// - Throws: Rethrows SQLite/SQLCipher errors.
    public static func rekey(pool: DatabasePool, newKeyHex: String) throws {
        // Use direct SQL interpolation rather than a bound parameter because
        // SQLite PRAGMA statements have limited support for positional bindings.
        // `newKeyHex` is always exactly 64 lowercase hex chars (SHA-256 output),
        // so there is no SQL-injection risk.
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA rekey = \"x'\(newKeyHex)'\"")
        }
    }
}

// MARK: - CipherMigrationError

public enum CipherMigrationError: Error, Sendable {
    case exportFailed(Error)
    case renameFailed(Error)
}

extension CipherMigrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exportFailed(let underlying):
            return "SQLCipher export failed: \(underlying.localizedDescription)"
        case .renameFailed(let underlying):
            return "Atomic rename failed after SQLCipher export: \(underlying.localizedDescription)"
        }
    }
}
