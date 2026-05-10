import Foundation
import GRDB
import os.log

// MARK: - AppDatabase + Cipher

extension AppDatabase {

    private static let cipherLogger = Logger(subsystem: "com.wiredpart.core", category: "AppDatabase+Cipher")

    // MARK: - Encrypted Pool Construction

    /// Open a file-based **encrypted** database using SQLCipher.
    ///
    /// The `keyHex` must be a 64-character lowercase hex string (32 bytes, i.e. a SHA-256
    /// digest encoded as hex). It is passed to SQLCipher as a passphrase so SQLCipher's
    /// PBKDF2 key derivation still runs.
    ///
    /// All SQLCipher PRAGMAs are issued inside `prepareDatabase` — the first closure called
    /// before any schema I/O — guaranteeing the key is set before any page is read.
    ///
    /// - Parameters:
    ///   - path: Filesystem path for the database file.
    ///   - keyHex: 64-char hex passphrase material derived by `CipherKeyManager`.
    /// - Returns: An open, migrated `AppDatabase` wrapping an encrypted `DatabasePool`.
    /// - Throws: Rethrows GRDB/SQLCipher errors (wrong key → `SQLITE_NOTADB`).
    public static func openEncryptedDatabase(atPath path: String, keyHex: String) throws -> AppDatabase {
        let pool = try makeEncryptedPool(path: path, keyHex: keyHex)
        return try AppDatabase(pool)
    }

    /// Build a `DatabasePool` configured for SQLCipher encryption.
    ///
    /// Prefer `openEncryptedDatabase(atPath:keyHex:)` which additionally runs migrations.
    /// Call this directly only when you need a raw pool (e.g. for import operations).
    public static func makeEncryptedPool(path: String, keyHex: String) throws -> DatabasePool {
        try validateCipherKeyHex(keyHex)

        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // Set the encryption key as a SQLCipher passphrase. Do not use
            // `x'<hex>'` raw-key notation here: raw keys bypass SQLCipher's KDF.
            //
            // `CipherKeyManager` first mixes the PIN with a device salt, then
            // SQLCipher applies its configured PBKDF2 work factor to this value.
            // For the device-bootstrap path, `keyHex` is random 32-byte material.
            try db.usePassphrase(keyHex)
            // Use 4096-byte pages (SQLCipher default; good for mobile I/O).
            try db.execute(sql: "PRAGMA cipher_page_size = 4096")
            // WAL mode for concurrent reads.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        return try DatabasePool(path: path, configuration: config)
    }

    // MARK: - One-Time Plaintext → Encrypted Migration (Option B)

    /// Migrate a plaintext SQLite database to a new SQLCipher-encrypted database.
    ///
    /// Run this **before** calling `openEncryptedDatabase(atPath:keyHex:)`.
    /// If the file does not exist, or is already encrypted, this is a no-op.
    ///
    /// **Option B algorithm** (atomic new-DB-with-import):
    /// 1. Probe-open without a key → success means file is plaintext.
    /// 2. Create a fresh SQLCipher-encrypted DB at `<path>.encrypted-tmp`.
    /// 3. Run the full `AppDatabase` schema migrator on the new encrypted DB.
    /// 4. ATTACH the old plaintext DB read-only as `old_db` (SQLCipher `KEY ''`).
    /// 5. Copy every user-data table with column-intersection `INSERT … SELECT`:
    ///    only columns present in **both** the old and new schema are copied so
    ///    that old DBs at an earlier migration level (fewer columns) are handled
    ///    correctly — new columns receive their schema DEFAULT values.
    /// 6. Verify per-table row counts match.
    /// 7. Detach old DB.
    /// 8. Restore the current schema-version record (may have been overwritten by the copy).
    /// 9. Close the new pool.
    /// 10. Atomic rename: `path` → `path.unencrypted.bak` (preserved), `path.encrypted-tmp` → `path`.
    ///
    /// On any failure the temp file is removed and the original plaintext DB is untouched.
    ///
    /// - Parameters:
    ///   - path: Canonical database file path.
    ///   - keyHex: 64-char hex passphrase material for the destination encrypted database.
    /// - Throws: Rethrows filesystem or SQLite errors.
    public static func migratePlaintextDBIfNeeded(atPath path: String, keyHex: String) throws {
        let fm = FileManager.default

        // No file → fresh install; nothing to migrate.
        guard fm.fileExists(atPath: path) else { return }

        // Idempotency probe: try opening WITHOUT a passphrase.
        // Success → file is plaintext → proceed with migration.
        // Any error → already encrypted (or corrupt) → skip.
        do {
            let probe = try DatabaseQueue(path: path)
            try probe.read { db in
                _ = try Row.fetchOne(db, sql: "SELECT 1 FROM sqlite_master LIMIT 1")
            }
            // `close()` is best-effort here: we've already confirmed the file is
            // plaintext. A close failure (e.g. transient FS flush error) must NOT
            // cause us to skip migration — otherwise the DB stays unencrypted.
            do {
                try probe.close()
            } catch {
                Self.cipherLogger.warning("Probe close failed (continuing): \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            // Opening or reading failed → file is already encrypted (or corrupt).
            return
        }

        let tempPath = path + ".encrypted-tmp"
        let bakPath  = path + ".unencrypted.bak"

        // Remove any leftover temp file from a previous failed attempt.
        for p in [tempPath, tempPath + "-wal", tempPath + "-shm"] {
            try? fm.removeItem(atPath: p)
        }

        // --- Step 1: Create fresh encrypted DB with full current schema ---
        let newPool = try makeEncryptedPool(path: tempPath, keyHex: keyHex)
        do {
            var migrator = DatabaseMigrator()
            AppDatabase.registerMigrations(&migrator)
            try migrator.migrate(newPool)

            // --- Step 2: ATTACH old plaintext DB and copy all user-data tables ---
            try newPool.writeWithoutTransaction { db in
                // Disable FK checks for bulk import (parent/child copy order irrelevant).
                // PRAGMA foreign_keys can only be changed outside of a transaction.
                try db.execute(sql: "PRAGMA foreign_keys = OFF")

                // Re-enable FK checks unconditionally when this closure exits,
                // regardless of whether DETACH or any subsequent step throws.
                defer {
                    do {
                        try db.execute(sql: "PRAGMA foreign_keys = ON")
                    } catch {
                        Self.cipherLogger.error("Failed to re-enable foreign_keys after import: \(error.localizedDescription, privacy: .public)")
                    }
                }

                // Attach old plaintext DB. SQLCipher uses KEY '' for unencrypted attachments.
                try db.execute(
                    sql: "ATTACH DATABASE ? AS old_db KEY ''",
                    arguments: [path]
                )

                // Enumerate tables present in the old DB (excluding SQLite internals and
                // grdb_migrations — the new DB's migration tracking is already correct).
                let oldTables = try String.fetchAll(
                    db,
                    sql: """
                        SELECT name FROM old_db.sqlite_master
                        WHERE type = 'table'
                          AND name NOT LIKE 'sqlite_%'
                          AND name != 'grdb_migrations'
                        ORDER BY rowid
                    """
                )

                // Tables present in the new encrypted DB (to guard against schema drift).
                let newTables = Set(try String.fetchAll(
                    db,
                    sql: """
                        SELECT name FROM main.sqlite_master
                        WHERE type = 'table'
                          AND name NOT LIKE 'sqlite_%'
                    """
                ))

                // Copy data for every table that exists in both the old and new DB.
                // Explicit intersecting columns let older plaintext schemas import into
                // the current schema while newer columns take their migration defaults.
                // INSERT OR REPLACE handles rows that the migrator may have seeded.
                //
                // Table names come from sqlite_master on our own database files, so they are
                // trusted. We additionally validate that each name contains only safe
                // characters (alphanumeric + underscore) as a defense-in-depth measure before
                // interpolating into SQL.
                //
                // Column-intersection copy: SELECT only columns that exist in the new schema.
                // This handles old DBs at an earlier migration level (fewer columns) and new
                // DBs that have added columns since — new columns receive their DEFAULT values.

                // Determine the validated set of tables to copy and pre-cache their new-schema
                // column lists so we don't re-query the (unchanging) encrypted DB inside the loop.
                let safeChars: CharacterSet = CharacterSet.alphanumerics.union(.init(charactersIn: "_"))
                let tablesToCopy = oldTables.filter {
                    newTables.contains($0) && $0.unicodeScalars.allSatisfy({ safeChars.contains($0) })
                }
                var newColsByTable: [String: [String]] = [:]
                for table in tablesToCopy {
                    newColsByTable[table] = try tableColumns(db, schema: "main", table: table)
                }

                var mismatchedTables: [String] = []
                for table in tablesToCopy {
                    let oldCols = try tableColumns(db, schema: "old_db", table: table)
                    let newCols = newColsByTable[table] ?? []
                    let oldColSet = Set(oldCols)
                    // Copy only columns present in both old and new schema; new columns get defaults.
                    let columnsToCopy = newCols.filter { oldColSet.contains($0) }
                    guard !columnsToCopy.isEmpty else {
                        throw CipherMigrationError.noSharedColumns(table)
                    }

                    let q = quotedIdentifier(table)
                    let columnList = columnsToCopy.map(quotedIdentifier).joined(separator: ", ")
                    try db.execute(sql: "INSERT OR REPLACE INTO main.\(q) (\(columnList)) SELECT \(columnList) FROM old_db.\(q)")

                    // --- Step 3: Verify row counts ---
                    let oldCount = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM old_db.\(q)")) ?? 0
                    let newCount = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM main.\(q)")) ?? 0
                    if newCount < oldCount {
                        mismatchedTables.append(table)
                    }
                }

                try db.execute(sql: "DETACH DATABASE old_db")

                if !mismatchedTables.isEmpty {
                    throw CipherMigrationError.rowCountMismatch(mismatchedTables)
                }
            }

            // --- Step 4: Stamp current schema version (data copy may have overwritten it) ---
            try newPool.write { db in
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO settings (key, value, category, updated_at)
                        VALUES ('db_schema_version', ?, 'system', datetime('now')),
                               ('last_migration_date', datetime('now'), 'system', datetime('now'))
                    """,
                    arguments: ["\(AppDatabase.schemaVersion)"]
                )
            }

            try newPool.close()
        } catch {
            try? newPool.close()
            for p in [tempPath, tempPath + "-wal", tempPath + "-shm"] {
                try? fm.removeItem(atPath: p)
            }
            throw error
        }

        // --- Step 5: Atomic rename ---
        // Original → .unencrypted.bak (preserved; deleted after 7 days by cleanupStaleBackup).
        // Temp encrypted → canonical path.
        do {
            for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: path + suffix) }
            try? fm.removeItem(atPath: bakPath)      // Remove stale backup if present.
            try fm.moveItem(atPath: path, toPath: bakPath)
            // Touch the backup so the 7-day retention window is measured from the time
            // of migration, not from the original DB file's last-modified timestamp.
            // (POSIX rename preserves the source's mtime; we want "age since migration".)
            do {
                try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: bakPath)
            } catch {
                Self.cipherLogger.warning("Failed to touch backup file (7-day window may be inaccurate): \(error.localizedDescription, privacy: .public)")
            }
            try fm.moveItem(atPath: tempPath, toPath: path)
        } catch {
            // Rename failed — temp is orphaned; clean it up. Original is still at `path`.
            for p in [tempPath, tempPath + "-wal", tempPath + "-shm"] {
                try? fm.removeItem(atPath: p)
            }
            throw CipherMigrationError.renameFailed(error)
        }
    }

    // MARK: - Backup Retention

    /// Seconds in a day (used for backup retention calculation).
    private static let secondsPerDay: Double = 86_400

    /// Delete the `.unencrypted.bak` file once it is stale (older than `retentionDays`).
    ///
    /// Call on every successful app launch after `openEncryptedDatabase` succeeds.
    /// The backup is retained for at least 7 days so the user can recover data if needed.
    ///
    /// - Parameters:
    ///   - path: Canonical database path (not the backup path).
    ///   - retentionDays: Number of days to keep the backup. Defaults to 7.
    public static func cleanupStaleUnencryptedBackup(atPath path: String, retentionDays: Int = 7) {
        let bakPath = path + ".unencrypted.bak"
        let fm = FileManager.default
        guard fm.fileExists(atPath: bakPath),
              let attrs = try? fm.attributesOfItem(atPath: bakPath),
              let modified = attrs[.modificationDate] as? Date else { return }
        let age = Date().timeIntervalSince(modified)
        if age >= Double(retentionDays) * Self.secondsPerDay {
            try? fm.removeItem(atPath: bakPath)
            try? fm.removeItem(atPath: bakPath + "-wal")
            try? fm.removeItem(atPath: bakPath + "-shm")
        }
    }

    // MARK: - Re-key (PIN change)

    /// Re-key an already-open encrypted `DatabasePool` to a new passphrase.
    ///
    /// SQLCipher's `PRAGMA rekey` is atomic — if it succeeds, the DB is re-encrypted;
    /// if the process is interrupted mid-write, SQLCipher rolls back to the old key.
    ///
    /// Note: The production app keeps its DB on the device-bound bootstrap key;
    /// this method is used by advanced callers and tests only.
    ///
    /// - Parameters:
    ///   - pool: An open, authenticated `DatabasePool`.
    ///   - newKeyHex: 64-char hex passphrase material for the new key.
    /// - Throws: Rethrows SQLite/SQLCipher errors.
    public static func rekey(pool: DatabasePool, newKeyHex: String) throws {
        try validateCipherKeyHex(newKeyHex)

        // Use direct SQL interpolation rather than a bound parameter because
        // SQLite PRAGMA statements have limited support for positional bindings.
        // `newKeyHex` is always exactly 64 lowercase hex chars (SHA-256 output),
        // so there is no SQL-injection risk.
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA rekey = '\(newKeyHex)'")
        }
    }

    private static func validateCipherKeyHex(_ value: String) throws {
        guard value.count == 64,
              value.allSatisfy({ $0.isHexDigit }) else {
            throw CipherMigrationError.invalidKeyMaterial
        }
    }

    private static func tableColumns(_ db: Database, schema: String, table: String) throws -> [String] {
        guard schema == "main" || schema == "old_db" else {
            throw CipherMigrationError.invalidSchemaName(schema)
        }
        return try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('\(table)', '\(schema)') ORDER BY cid")
    }

    private static func quotedIdentifier(_ value: String) -> String {
        "\"\(value)\""
    }
}

// MARK: - CipherMigrationError

public enum CipherMigrationError: Error, Sendable {
    case exportFailed(Error)
    case renameFailed(Error)
    /// One or more tables had a row-count mismatch after the import.
    case rowCountMismatch([String])
    /// The passphrase material must be a 64-character hex digest.
    case invalidKeyMaterial
    /// A source table and destination table had no columns in common.
    case noSharedColumns(String)
    /// Internal guard against unsupported schema interpolation.
    case invalidSchemaName(String)
}

extension CipherMigrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exportFailed(let underlying):
            return "SQLCipher export failed: \(underlying.localizedDescription)"
        case .renameFailed(let underlying):
            return "Atomic rename failed after SQLCipher import: \(underlying.localizedDescription)"
        case .rowCountMismatch(let tables):
            return "Row-count mismatch after import for tables: \(tables.joined(separator: ", "))"
        case .invalidKeyMaterial:
            return "Invalid SQLCipher key material."
        case .noSharedColumns(let table):
            return "No shared columns while importing table: \(table)"
        case .invalidSchemaName(let schema):
            return "Invalid schema name: \(schema)"
        }
    }
}
