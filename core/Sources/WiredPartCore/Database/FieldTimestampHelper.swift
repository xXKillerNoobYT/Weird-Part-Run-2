import Foundation
import GRDB

/// Maintains per-field LWW timestamps for synced records.
public enum FieldTimestampHelper {
    public static let columnName = "_field_timestamps"

    /// Merge a timestamp for each touched field into a row's `_field_timestamps` JSON map.
    public static func stamp(
        _ fields: [String],
        table: String,
        rowId: Int64,
        timestamp: String = CoreFormatters.iso8601Fractional.string(from: Date()),
        in db: Database
    ) throws {
        let uniqueFields = Array(Set(fields)).sorted()
        guard !uniqueFields.isEmpty else { return }

        try validate(table: table, fields: uniqueFields, in: db)

        let existing: String? = try String.fetchOne(
            db,
            sql: "SELECT \(quotedIdentifier(columnName)) FROM \(quotedIdentifier(table)) WHERE id = ?",
            arguments: [rowId]
        )

        var timestamps = decode(existing)
        for field in uniqueFields {
            timestamps[field] = timestamp
        }

        let encoded = try encode(timestamps)
        try db.execute(
            sql: "UPDATE \(quotedIdentifier(table)) SET \(quotedIdentifier(columnName)) = ? WHERE id = ?",
            arguments: [encoded, rowId]
        )
    }

    static func decode(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func encode(_ timestamps: [String: String]) throws -> String {
        let data = try JSONEncoder().encode(timestamps)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func validate(table: String, fields: [String], in db: Database) throws {
        guard ConflictResolver.isAllowedTable(table) else {
            throw DatabaseError(message: "Cannot stamp field timestamps for unsynced table \(table)")
        }

        let columns = Set(try db.columns(in: table).map(\.name))
        guard columns.contains(columnName) else {
            throw DatabaseError(message: "Table \(table) is missing \(columnName)")
        }

        for field in fields {
            guard field != "id", field != columnName, columns.contains(field) else {
                throw DatabaseError(message: "Cannot stamp unknown synced field \(table).\(field)")
            }
        }
    }

    private static func quotedIdentifier(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
