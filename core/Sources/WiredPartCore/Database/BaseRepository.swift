import Foundation
import GRDB

/// Generic CRUD repository for local SQLite tables.
///
/// Every domain repo extends this with table-specific queries.
/// All writes automatically go through `ChangeTracker.trackChange()`
/// for sync logging, unless explicitly opted out via `track: false`.
///
/// Ported from: `src/local/repos/base-repo.ts`
///
/// CONCURRENCY INVARIANT (#222 — `@unchecked Sendable` contract):
/// This base class and all subclasses MUST NOT add mutable stored properties
/// (`var`) — the `@unchecked Sendable` conformance disables compiler-enforced
/// thread safety, and the only reason it's safe is that all state here is
/// `let`-immutable. All state mutation happens through `AppDatabase`, which
/// serializes writes via GRDB's writer queue. If you need per-instance caching
/// or state, use an actor or an NSLock-guarded accessor (see PeerDiscovery).
public class BaseRepository: @unchecked Sendable {
    public let tableName: String
    public let primaryKey: String
    private let db: AppDatabase

    public init(db: AppDatabase, tableName: String, primaryKey: String = "id") {
        self.db = db
        self.tableName = tableName
        self.primaryKey = primaryKey
    }

    // MARK: - Read Operations

    /// Get a single record by primary key.
    public func getById(_ id: Int64) throws -> Row? {
        try db.writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM \(self.tableName) WHERE \(self.primaryKey) = ?",
                arguments: [id]
            )
        }
    }

    /// Get all records matching an optional WHERE clause.
    ///
    /// Fix #223: `limit` defaults to 1000 to prevent accidental full-table scans
    /// on large tables (parts, stock_movements, stock). Pass `limit: nil` to opt
    /// into unlimited results for cases that genuinely need it.
    public func findAll(
        where whereClause: String? = nil,
        params: [any DatabaseValueConvertible] = [],
        orderBy: String? = nil,
        limit: Int? = 1000,
        offset: Int? = nil
    ) throws -> [Row] {
        try db.writer.read { db in
            var sql = "SELECT * FROM \(self.tableName)"
            if let whereClause { sql += " WHERE \(whereClause)" }
            if let orderBy { sql += " ORDER BY \(orderBy)" }
            if let limit { sql += " LIMIT \(limit)" }
            if let offset { sql += " OFFSET \(offset)" }
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(params))
        }
    }

    /// Count records matching an optional WHERE clause.
    public func count(
        where whereClause: String? = nil,
        params: [any DatabaseValueConvertible] = []
    ) throws -> Int {
        try db.writer.read { db in
            var sql = "SELECT COUNT(*) FROM \(self.tableName)"
            if let whereClause { sql += " WHERE \(whereClause)" }
            return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(params)) ?? 0
        }
    }

    // MARK: - Write Operations

    /// Insert a record and track the change for sync.
    /// Returns the new row's ID.
    ///
    /// Values are `DatabaseValue` — use `DatabaseValue.null` for SQL NULL,
    /// or convert via `.databaseValue` on any `DatabaseValueConvertible`.
    @discardableResult
    public func insert(
        _ data: [String: DatabaseValue],
        track: Bool = true,
        deviceId: String? = nil
    ) throws -> Int64 {
        let keys = Array(data.keys)
        let placeholders = keys.map { _ in "?" }.joined(separator: ", ")
        // keys is derived from data.keys, so every subscript is guaranteed present
        let values = keys.compactMap { data[$0] }

        let newId = try db.writer.write { db -> Int64 in
            try db.execute(
                sql: "INSERT INTO \(self.tableName) (\(keys.joined(separator: ", "))) VALUES (\(placeholders))",
                arguments: StatementArguments(values)
            )
            return db.lastInsertedRowID
        }

        if track {
            try ChangeTracker.trackChange(
                db: self.db,
                tableName: tableName,
                recordId: newId,
                operation: .insert,
                changedFields: data.mapValues { $0 as Any },
                deviceId: deviceId
            )
        }

        return newId
    }

    /// Update a record by primary key and track the change.
    /// Returns true if a row was actually modified.
    @discardableResult
    public func update(
        _ id: Int64,
        data: [String: DatabaseValue],
        track: Bool = true,
        deviceId: String? = nil
    ) throws -> Bool {
        let keys = Array(data.keys)
        guard !keys.isEmpty else { return false }

        // Fetch old values for conflict resolution
        var oldValues: [String: Any]?
        if track {
            if let existing = try getById(id) {
                oldValues = [:]
                for key in keys {
                    oldValues?[key] = existing[key] as Any
                }
            }
        }

        let setClauses = keys.map { "\($0) = ?" }.joined(separator: ", ")
        var values: [DatabaseValue] = keys.compactMap { data[$0] }
        values.append(id.databaseValue)

        let changes = try db.writer.write { db -> Int in
            try db.execute(
                sql: "UPDATE \(self.tableName) SET \(setClauses) WHERE \(self.primaryKey) = ?",
                arguments: StatementArguments(values)
            )
            return db.changesCount
        }

        if changes > 0 && track {
            try ChangeTracker.trackChange(
                db: self.db,
                tableName: tableName,
                recordId: id,
                operation: .update,
                changedFields: data.mapValues { $0 as Any },
                oldValues: oldValues,
                deviceId: deviceId
            )
        }

        return changes > 0
    }

    /// Delete a record and track the change.
    /// Returns true if a row was actually deleted.
    @discardableResult
    public func delete(
        _ id: Int64,
        track: Bool = true,
        deviceId: String? = nil
    ) throws -> Bool {
        var oldValues: [String: Any]?
        if track {
            if let existing = try getById(id) {
                oldValues = Dictionary(
                    uniqueKeysWithValues: existing.columnNames.map { ($0, existing[$0] as Any) }
                )
            }
        }

        let changes = try db.writer.write { db -> Int in
            try db.execute(
                sql: "DELETE FROM \(self.tableName) WHERE \(self.primaryKey) = ?",
                arguments: [id]
            )
            return db.changesCount
        }

        if changes > 0 && track {
            try ChangeTracker.trackChange(
                db: self.db,
                tableName: tableName,
                recordId: id,
                operation: .delete,
                oldValues: oldValues,
                deviceId: deviceId
            )
        }

        return changes > 0
    }

    // MARK: - Raw Queries

    /// Run a raw read query (for complex joins).
    public func rawQuery(_ sql: String, params: [any DatabaseValueConvertible] = []) throws -> [Row] {
        try db.writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(params))
        }
    }

    /// Run a raw write query (for complex updates). Returns the number of changed rows.
    @discardableResult
    public func rawRun(_ sql: String, params: [any DatabaseValueConvertible] = []) throws -> Int {
        try db.writer.write { db in
            try db.execute(sql: sql, arguments: StatementArguments(params))
            return db.changesCount
        }
    }
}

// MARK: - DatabaseValue Convenience

extension DatabaseValue {
    /// Create a DatabaseValue from a String or nil.
    public static func from(_ value: String?) -> DatabaseValue {
        value?.databaseValue ?? .null
    }

    /// Create a DatabaseValue from an Int or nil.
    public static func from(_ value: Int?) -> DatabaseValue {
        value?.databaseValue ?? .null
    }

    /// Create a DatabaseValue from an Int64 or nil.
    public static func from(_ value: Int64?) -> DatabaseValue {
        value?.databaseValue ?? .null
    }

    /// Create a DatabaseValue from a Double or nil.
    public static func from(_ value: Double?) -> DatabaseValue {
        value?.databaseValue ?? .null
    }
}
