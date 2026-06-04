import Foundation
import GRDB

/// Central database access point for the WiredPart application.
/// Manages the GRDB database connection and runs migrations on initialization.
public final class AppDatabase: Sendable {
    /// The underlying GRDB database writer (DatabasePool for file-based, DatabaseQueue for in-memory).
    public let writer: any DatabaseWriter

    /// The total number of registered migrations. Update when adding new migrations.
    /// Migrations are 000-099.
    public static let schemaVersion = 99

    /// Initialize with an existing database writer and run all migrations.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        var migrator = DatabaseMigrator()
        Self.registerMigrations(&migrator)
        try migrator.migrate(writer)

        // Record schema version after successful migration
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO settings (key, value, category, updated_at)
                VALUES ('db_schema_version', ?, 'system', datetime('now')),
                       ('last_migration_date', datetime('now'), 'system', datetime('now'))
                """, arguments: ["\(Self.schemaVersion)"])
        }
    }

    /// Open a file-based database at the given path.
    /// Uses WAL mode via DatabasePool for concurrent reads.
    public static func openDatabase(atPath path: String) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrency
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        return try AppDatabase(pool)
    }

    /// Open an in-memory database for testing.
    public static func openInMemoryDatabase() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue)
    }

    // MARK: - Backup & Restore

    /// Create a backup of the database before running migrations.
    /// Returns the backup file path, or nil if backup failed.
    @discardableResult
    public static func backupDatabase(atPath path: String) -> String? {
        let fileManager = FileManager.default
        let backupDir = (path as NSString).deletingLastPathComponent + "/Backups"
        do {
            try fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupPath = backupDir + "/pre-migration-\(timestamp).sqlite"

        do {
            // Only back up if the source file exists
            guard fileManager.fileExists(atPath: path) else { return nil }

            try fileManager.copyItem(atPath: path, toPath: backupPath)

            // Also copy WAL and SHM files if they exist
            for suffix in ["-wal", "-shm"] {
                let src = path + suffix
                let dst = backupPath + suffix
                if fileManager.fileExists(atPath: src) {
                    try? fileManager.copyItem(atPath: src, toPath: dst)
                }
            }

            // Keep only last 5 pre-migration backups
            let allFiles = try fileManager.contentsOfDirectory(atPath: backupDir)
            let backups = allFiles
                .filter { $0.hasPrefix("pre-migration-") && $0.hasSuffix(".sqlite") }
                .sorted()
            if backups.count > 5 {
                for old in backups.prefix(backups.count - 5) {
                    let oldPath = backupDir + "/" + old
                    try? fileManager.removeItem(atPath: oldPath)
                    // Also remove WAL/SHM for old backups
                    try? fileManager.removeItem(atPath: oldPath + "-wal")
                    try? fileManager.removeItem(atPath: oldPath + "-shm")
                }
            }

            return backupPath
        } catch {
            return nil
        }
    }

    /// Restore database from a backup file.
    public static func restoreDatabase(from backupPath: String, to dbPath: String) throws {
        let fileManager = FileManager.default
        // Remove current DB files
        try? fileManager.removeItem(atPath: dbPath)
        try? fileManager.removeItem(atPath: dbPath + "-wal")
        try? fileManager.removeItem(atPath: dbPath + "-shm")
        // Copy backup into place
        try fileManager.copyItem(atPath: backupPath, toPath: dbPath)
        // Restore WAL/SHM if they exist
        for suffix in ["-wal", "-shm"] {
            let src = backupPath + suffix
            if fileManager.fileExists(atPath: src) {
                try? fileManager.copyItem(atPath: src, toPath: dbPath + suffix)
            }
        }
    }
}
