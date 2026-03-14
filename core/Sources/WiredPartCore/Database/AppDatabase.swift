import Foundation
import GRDB

/// Central database access point for the WiredPart application.
/// Manages the GRDB database connection and runs migrations on initialization.
public final class AppDatabase: Sendable {
    /// The underlying GRDB database writer (DatabasePool for file-based, DatabaseQueue for in-memory).
    public let writer: any DatabaseWriter

    /// Initialize with an existing database writer and run all migrations.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        var migrator = DatabaseMigrator()
        Self.registerMigrations(&migrator)
        try migrator.migrate(writer)
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
}
