import Foundation
import GRDB

/// Notebooks Service — unified notebook system for job notebooks, general notebooks,
/// templates, and their entries (todos, notes, checklists).
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Unified Notebook System (Phase 4.5)
public final class NotebooksService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum NotebooksError: Error, Sendable {
        case notebookNotFound(Int64)
        case entryNotFound(Int64)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A notebook row for list views with summary info.
    public struct NotebookListItem: Sendable, Identifiable {
        public let id: Int64
        public let title: String
        public let notebookType: String
        public let jobName: String?
        public let createdByName: String
        public let entryCount: Int
        public let status: String
        public let updatedAt: String?

        public init(
            id: Int64, title: String, notebookType: String, jobName: String?,
            createdByName: String, entryCount: Int, status: String, updatedAt: String?
        ) {
            self.id = id
            self.title = title
            self.notebookType = notebookType
            self.jobName = jobName
            self.createdByName = createdByName
            self.entryCount = entryCount
            self.status = status
            self.updatedAt = updatedAt
        }
    }

    /// A single notebook entry row.
    public struct NotebookEntryRow: Sendable, Identifiable {
        public let id: Int64
        public let entryType: String
        public let content: String
        public let createdByName: String
        public let sortOrder: Int
        public let isCompleted: Bool
        public let createdAt: String?

        public init(
            id: Int64, entryType: String, content: String,
            createdByName: String, sortOrder: Int, isCompleted: Bool,
            createdAt: String?
        ) {
            self.id = id
            self.entryType = entryType
            self.content = content
            self.createdByName = createdByName
            self.sortOrder = sortOrder
            self.isCompleted = isCompleted
            self.createdAt = createdAt
        }
    }

    /// Full notebook detail with all entries.
    public struct NotebookDetail: Sendable {
        public let id: Int64
        public let title: String
        public let notebookType: String
        public let jobId: Int64?
        public let jobName: String?
        public let createdByName: String
        public let content: String?
        public let status: String
        public let createdAt: String?
        public let updatedAt: String?
        public let entries: [NotebookEntryRow]

        public init(
            id: Int64, title: String, notebookType: String,
            jobId: Int64?, jobName: String?,
            createdByName: String, content: String?,
            status: String, createdAt: String?, updatedAt: String?,
            entries: [NotebookEntryRow]
        ) {
            self.id = id
            self.title = title
            self.notebookType = notebookType
            self.jobId = jobId
            self.jobName = jobName
            self.createdByName = createdByName
            self.content = content
            self.status = status
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.entries = entries
        }
    }

    /// Aggregate notebooks statistics.
    public struct NotebooksStats: Sendable {
        public let totalNotebooks: Int
        public let jobNotebooks: Int
        public let generalNotebooks: Int

        public init(totalNotebooks: Int, jobNotebooks: Int, generalNotebooks: Int) {
            self.totalNotebooks = totalNotebooks
            self.jobNotebooks = jobNotebooks
            self.generalNotebooks = generalNotebooks
        }
    }

    // =========================================================================
    // MARK: - 1. List Notebooks
    // =========================================================================

    /// List notebooks with optional type and job filters.
    public func listNotebooks(notebookType: String? = nil, jobId: Int64? = nil) throws -> [NotebookListItem] {
        do {
            return try db.writer.read { dbConn -> [NotebookListItem] in
                var whereClauses = ["n.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let notebookType, !notebookType.isEmpty {
                    whereClauses.append("n.notebook_type = ?")
                    args.append(notebookType)
                }
                if let jobId {
                    whereClauses.append("n.job_id = ?")
                    args.append(jobId)
                }

                let sql = """
                    SELECT n.id, n.title, n.notebook_type, n.status, n.updated_at,
                           j.job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name,
                           COALESCE((SELECT COUNT(*) FROM notebook_entries ne
                                     WHERE ne.notebook_id = n.id AND ne.deleted_at IS NULL), 0) AS entry_count
                    FROM notebooks n
                    LEFT JOIN jobs j ON j.id = n.job_id
                    LEFT JOIN users u ON u.id = n.created_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY n.updated_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    NotebookListItem(
                        id: row["id"] ?? 0,
                        title: row["title"] ?? "",
                        notebookType: row["notebook_type"] ?? "general",
                        jobName: row["job_name"] as String?,
                        createdByName: row["created_by_name"] ?? "Unknown",
                        entryCount: row["entry_count"] ?? 0,
                        status: row["status"] ?? "active",
                        updatedAt: row["updated_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Notebook Detail
    // =========================================================================

    /// Get a single notebook by ID with full detail and all entries.
    public func getNotebookDetail(id: Int64) throws -> NotebookDetail {
        let result: NotebookDetail? = try db.writer.read { dbConn -> NotebookDetail? in
            // Fetch the notebook header
            let headerSQL = """
                SELECT n.id, n.title, n.notebook_type, n.job_id, n.content, n.status,
                       n.created_at, n.updated_at,
                       j.job_name,
                       COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name
                FROM notebooks n
                LEFT JOIN jobs j ON j.id = n.job_id
                LEFT JOIN users u ON u.id = n.created_by
                WHERE n.id = ? AND n.deleted_at IS NULL
                """
            guard let headerRow = try Row.fetchOne(dbConn, sql: headerSQL, arguments: [id]) else {
                return nil
            }

            // Fetch the entries
            let entriesSQL = """
                SELECT ne.id, ne.entry_type, ne.content, ne.sort_order, ne.is_completed,
                       ne.created_at,
                       COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name
                FROM notebook_entries ne
                LEFT JOIN users u ON u.id = ne.created_by
                WHERE ne.notebook_id = ? AND ne.deleted_at IS NULL
                ORDER BY ne.sort_order ASC, ne.created_at ASC
                """
            let entryRows = try Row.fetchAll(dbConn, sql: entriesSQL, arguments: [id])

            let entries = entryRows.map { row in
                NotebookEntryRow(
                    id: row["id"] ?? 0,
                    entryType: row["entry_type"] ?? "note",
                    content: row["content"] ?? "",
                    createdByName: row["created_by_name"] ?? "Unknown",
                    sortOrder: row["sort_order"] ?? 0,
                    isCompleted: (row["is_completed"] as Int?) == 1,
                    createdAt: row["created_at"] as String?
                )
            }

            return NotebookDetail(
                id: headerRow["id"] ?? 0,
                title: headerRow["title"] ?? "",
                notebookType: headerRow["notebook_type"] ?? "general",
                jobId: headerRow["job_id"] as Int64?,
                jobName: headerRow["job_name"] as String?,
                createdByName: headerRow["created_by_name"] ?? "Unknown",
                content: headerRow["content"] as String?,
                status: headerRow["status"] ?? "active",
                createdAt: headerRow["created_at"] as String?,
                updatedAt: headerRow["updated_at"] as String?,
                entries: entries
            )
        }
        guard let result else { throw NotebooksError.notebookNotFound(id) }
        return result
    }

    // =========================================================================
    // MARK: - 3. Templates
    // =========================================================================

    /// List notebook templates (filters for notebook_type = 'template').
    public func listTemplates() throws -> [NotebookListItem] {
        return try listNotebooks(notebookType: "template")
    }

    // =========================================================================
    // MARK: - 4. Create Notebook
    // =========================================================================

    /// Create a new notebook. Returns the inserted row ID.
    @discardableResult
    public func createNotebook(
        title: String,
        notebookType: String,
        jobId: Int64? = nil,
        createdBy: Int64
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO notebooks
                    (title, notebook_type, job_id, created_by, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'active', datetime('now'), datetime('now'))
                    """,
                arguments: [title, notebookType, jobId, createdBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 5. Notebooks Stats
    // =========================================================================

    /// Get aggregate notebooks statistics: total, job-linked, and general counts.
    public func getNotebooksStats() throws -> NotebooksStats {
        let totalNotebooks = try safeCount(
            sql: "SELECT COUNT(*) FROM notebooks WHERE deleted_at IS NULL"
        )

        let jobNotebooks = try safeCount(
            sql: "SELECT COUNT(*) FROM notebooks WHERE job_id IS NOT NULL AND deleted_at IS NULL"
        )

        let generalNotebooks = try safeCount(
            sql: "SELECT COUNT(*) FROM notebooks WHERE job_id IS NULL AND notebook_type != 'template' AND deleted_at IS NULL"
        )

        return NotebooksStats(
            totalNotebooks: totalNotebooks,
            jobNotebooks: jobNotebooks,
            generalNotebooks: generalNotebooks
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }
}
