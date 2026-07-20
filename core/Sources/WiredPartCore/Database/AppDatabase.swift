import Foundation
import GRDB

/// Central database access point for the WiredPart application.
/// Manages the GRDB database connection and runs migrations on initialization.
public final class AppDatabase: Sendable {
    /// The underlying GRDB database writer (DatabasePool for file-based, DatabaseQueue for in-memory).
    public let writer: any DatabaseWriter
    private static let inMemoryTemplateCache = InMemoryTemplateCache()

    private final class InMemoryTemplateCache: @unchecked Sendable {
        let lock = NSLock()
        var path: String?
    }

    /// The total number of registered migrations. Update when adding new migrations.
    /// Migrations are 000-113.
    public static let schemaVersion = 113

    /// Initialize with an existing database writer and run all migrations.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrate(writer)
    }

    private init(_ writer: any DatabaseWriter, runMigrations: Bool) throws {
        self.writer = writer
        if runMigrations {
            try Self.migrate(writer)
        }
    }

    private static func migrate(_ writer: any DatabaseWriter) throws {
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
        config.qos = .userInitiated
        // Pin all GRDB serialized queues to a concurrent userInitiated target queue.
        // Without this, `DispatchQueue.sync` from a lower-QoS caller (e.g. a .utility
        // sync worker) runs the SQLite work on the caller's thread at the caller's
        // QoS; a user-interactive thread that then waits on the pool's semaphore
        // trips libdispatch's priority-inversion warning at GRDB Pool.swift line 80.
        // The target queue must be concurrent for DatabasePool so reader connections
        // still execute in parallel.
        config.targetQueue = makeDatabaseTargetQueue()
        config.prepareDatabase { db in
            // Enable WAL mode for better concurrency
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        return try AppDatabase(pool)
    }

    /// Build a concurrent userInitiated dispatch queue used as the GRDB target
    /// queue. See `openDatabase(atPath:)` for the rationale.
    static func makeDatabaseTargetQueue() -> DispatchQueue {
        DispatchQueue(
            label: "com.wiredpart.db.target",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    /// Open an in-memory database for testing.
    public static func openInMemoryDatabase() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let templatePath = try migratedInMemoryTemplatePath()
        let queue = try DatabaseQueue.inMemoryCopy(fromPath: templatePath, configuration: config)
        return try AppDatabase(queue, runMigrations: false)
    }

    private static func migratedInMemoryTemplatePath() throws -> String {
        let cache = inMemoryTemplateCache
        cache.lock.lock()
        defer { cache.lock.unlock() }

        if let path = cache.path, FileManager.default.fileExists(atPath: path) {
            return path
        }

        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("WiredPartCore-schema-\(schemaVersion)-test-template-\(ProcessInfo.processInfo.processIdentifier).sqlite")
        if !FileManager.default.fileExists(atPath: path) {
            var config = Configuration()
            config.foreignKeysEnabled = true
            let queue = try DatabaseQueue(path: path, configuration: config)
            _ = try AppDatabase(queue)
        }
        cache.path = path
        return path
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
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss_SSS"
        let timestamp = dateFormatter.string(from: Date())
        let uniqueId = UUID().uuidString.prefix(8)
        let backupPath = backupDir + "/pre-migration-\(timestamp)-\(uniqueId).sqlite"

        do {
            // Only back up if the source file exists
            guard fileManager.fileExists(atPath: path) else { return nil }

            try fileManager.copyItem(atPath: path, toPath: backupPath)

            // Also copy WAL and SHM files if they exist. These sidecars are part
            // of the durable SQLite snapshot while WAL mode is enabled; silently
            // skipping one can make the pre-migration rollback backup stale.
            for suffix in ["-wal", "-shm"] {
                let src = path + suffix
                let dst = backupPath + suffix
                if fileManager.fileExists(atPath: src) {
                    try fileManager.copyItem(atPath: src, toPath: dst)
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
        try restoreDatabase(from: backupPath, to: dbPath, willPromoteStagedBackup: nil)
    }

    static func restoreDatabase(
        from backupPath: String,
        to dbPath: String,
        willPromoteStagedBackup: (() throws -> Void)?
    ) throws {
        let fileManager = FileManager.default
        let restoreId = UUID().uuidString
        let stagedPath = dbPath + ".restore-\(restoreId).tmp"
        let rollbackPath = dbPath + ".restore-\(restoreId).rollback"
        var shouldCleanRollback = true

        func removeDatabaseFiles(at path: String) {
            try? fileManager.removeItem(atPath: path)
            try? fileManager.removeItem(atPath: path + "-wal")
            try? fileManager.removeItem(atPath: path + "-shm")
        }

        func moveDatabaseFiles(from source: String, to destination: String) throws {
            if fileManager.fileExists(atPath: source) {
                try fileManager.moveItem(atPath: source, toPath: destination)
            }
            for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: source + suffix) {
                try fileManager.moveItem(atPath: source + suffix, toPath: destination + suffix)
            }
        }

        func removeDestinationFilesForRollbackBundle() {
            if fileManager.fileExists(atPath: rollbackPath) {
                try? fileManager.removeItem(atPath: dbPath)
            }
            for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: rollbackPath + suffix) {
                try? fileManager.removeItem(atPath: dbPath + suffix)
            }
        }

        removeDatabaseFiles(at: stagedPath)
        removeDatabaseFiles(at: rollbackPath)
        defer {
            removeDatabaseFiles(at: stagedPath)
            if shouldCleanRollback {
                removeDatabaseFiles(at: rollbackPath)
            }
        }

        // Stage the backup bundle before touching the live database. This preserves
        // the current DB when the backup path is stale, missing, or unreadable.
        try fileManager.copyItem(atPath: backupPath, toPath: stagedPath)
        for suffix in ["-wal", "-shm"] {
            let src = backupPath + suffix
            if fileManager.fileExists(atPath: src) {
                try fileManager.copyItem(atPath: src, toPath: stagedPath + suffix)
            }
        }

        do {
            try moveDatabaseFiles(from: dbPath, to: rollbackPath)
            try willPromoteStagedBackup?()
            try moveDatabaseFiles(from: stagedPath, to: dbPath)
        } catch {
            if fileManager.fileExists(atPath: rollbackPath)
                || fileManager.fileExists(atPath: rollbackPath + "-wal")
                || fileManager.fileExists(atPath: rollbackPath + "-shm") {
                removeDestinationFilesForRollbackBundle()
                do {
                    try moveDatabaseFiles(from: rollbackPath, to: dbPath)
                } catch {
                    shouldCleanRollback = false
                    throw error
                }
            }
            throw error
        }
    }
}
