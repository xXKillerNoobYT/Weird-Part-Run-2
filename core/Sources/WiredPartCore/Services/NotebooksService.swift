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
    private let auth: AuthService

    public init(db: AppDatabase, auth: AuthService? = nil) {
        self.db = db
        self.auth = auth ?? AuthService(db: db)
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum NotebooksError: Error, LocalizedError, Sendable {
        case notebookNotFound(Int64)
        case entryNotFound(Int64)
        case requiredFieldEmpty
        case invalidDuration(Int64)
        case insufficientPermissions(required: String)

        public var errorDescription: String? {
            switch self {
            case .insufficientPermissions(let required):
                return "You don't have permission to perform this action (required: \(required))."
            case .notebookNotFound(let id):
                return "Notebook \(id) not found."
            case .entryNotFound(let id):
                return "Notebook entry \(id) not found."
            case .requiredFieldEmpty:
                return "A required field is empty."
            case .invalidDuration(let duration):
                return "Invalid duration: \(duration)."
            }
        }
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
        // Block fields
        public let title: String?
        public let blockType: String
        public let blockData: String?
        public let headingLevel: Int?
        public let checklistItems: String?
        public let photoPath: String?
        public let referenceType: String?
        public let referenceId: Int64?
        // Classification fields (45D)
        public let workClassification: String?
        public let classificationReviewed: Bool
        public let warrantyTimerEnd: String?
        public let isQuestion: Bool

        public init(
            id: Int64, entryType: String, content: String,
            createdByName: String, sortOrder: Int, isCompleted: Bool,
            createdAt: String?,
            title: String? = nil, blockType: String = "text",
            blockData: String? = nil, headingLevel: Int? = nil,
            checklistItems: String? = nil, photoPath: String? = nil,
            referenceType: String? = nil, referenceId: Int64? = nil,
            workClassification: String? = nil, classificationReviewed: Bool = false,
            warrantyTimerEnd: String? = nil, isQuestion: Bool = false
        ) {
            self.id = id
            self.entryType = entryType
            self.content = content
            self.createdByName = createdByName
            self.sortOrder = sortOrder
            self.isCompleted = isCompleted
            self.createdAt = createdAt
            self.title = title
            self.blockType = blockType
            self.blockData = blockData
            self.headingLevel = headingLevel
            self.checklistItems = checklistItems
            self.photoPath = photoPath
            self.referenceType = referenceType
            self.referenceId = referenceId
            self.workClassification = workClassification
            self.classificationReviewed = classificationReviewed
            self.warrantyTimerEnd = warrantyTimerEnd
            self.isQuestion = isQuestion
        }
    }

    /// A warranty work classification waiting for manager review.
    public struct PendingWarrantyClassification: Sendable, Identifiable {
        public let id: Int64
        public let entryTitle: String
        public let entryContent: String
        public let requestedClassification: String
        public let requestedByName: String
        public let jobName: String
        public let createdAt: String

        public init(
            id: Int64,
            entryTitle: String,
            entryContent: String,
            requestedClassification: String,
            requestedByName: String,
            jobName: String,
            createdAt: String
        ) {
            self.id = id
            self.entryTitle = entryTitle
            self.entryContent = entryContent
            self.requestedClassification = requestedClassification
            self.requestedByName = requestedByName
            self.jobName = jobName
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
                    LEFT JOIN jobs j ON j.id = n.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = n.created_by AND u.deleted_at IS NULL
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
                LEFT JOIN jobs j ON j.id = n.job_id AND j.deleted_at IS NULL
                LEFT JOIN users u ON u.id = n.created_by AND u.deleted_at IS NULL
                WHERE n.id = ? AND n.deleted_at IS NULL
                """
            guard let headerRow = try Row.fetchOne(dbConn, sql: headerSQL, arguments: [id]) else {
                return nil
            }

            // Fetch the entries
            let entriesSQL = """
                SELECT ne.id, ne.entry_type, ne.title, ne.content, ne.sort_order,
                       COALESCE(ne.is_completed, 0) as is_completed, ne.created_at,
                       ne.block_type, ne.block_data, ne.heading_level, ne.checklist_items,
                       ne.photo_path, ne.reference_type, ne.reference_id,
                       ne.work_classification, COALESCE(ne.classification_reviewed, 0) as classification_reviewed,
                       ne.warranty_timer_end, COALESCE(ne.is_question, 0) as is_question,
                       COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name
                FROM notebook_entries ne
                LEFT JOIN users u ON u.id = ne.created_by AND u.deleted_at IS NULL
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
                    createdAt: row["created_at"] as String?,
                    title: row["title"] as String?,
                    blockType: row["block_type"] ?? "text",
                    blockData: row["block_data"] as String?,
                    headingLevel: row["heading_level"] as Int?,
                    checklistItems: row["checklist_items"] as String?,
                    photoPath: row["photo_path"] as String?,
                    referenceType: row["reference_type"] as String?,
                    referenceId: row["reference_id"] as Int64?,
                    workClassification: row["work_classification"] as String?,
                    classificationReviewed: (row["classification_reviewed"] as Int?) == 1,
                    warrantyTimerEnd: row["warranty_timer_end"] as String?,
                    isQuestion: (row["is_question"] as Int?) == 1
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
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
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
    // MARK: - 5. Add Notebook Entry
    // =========================================================================

    /// Adds a new entry to a notebook section.
    /// If no section exists yet, creates a default "General" section first.
    @discardableResult
    public func addNotebookEntry(
        notebookId: Int64,
        title: String,
        content: String? = nil,
        entryType: String = "note",
        createdBy: Int64
    ) throws -> Int64 {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
            // Get or create a default section
            var sectionId: Int64
            if let existing = try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM notebook_sections WHERE notebook_id = ? AND deleted_at IS NULL LIMIT 1",
                arguments: [notebookId]
            ) {
                sectionId = existing
            } else {
                try dbConn.execute(
                    sql: """
                        INSERT INTO notebook_sections (notebook_id, name, sort_order, created_at)
                        VALUES (?, 'General', 0, datetime('now'))
                        """,
                    arguments: [notebookId]
                )
                sectionId = dbConn.lastInsertedRowID
            }

            // Insert the entry
            // Fix #180: include notebook_id so direct lookups and badge-count queries work.
            // Previously, notebook_id was NULL — entries were only reachable via section_id JOIN.
            try dbConn.execute(
                sql: """
                    INSERT INTO notebook_entries
                    (notebook_id, section_id, title, content, entry_type, created_by, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, 0, datetime('now'), datetime('now'))
                    """,
                arguments: [notebookId, sectionId, title, content, entryType, createdBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 6. Complete / Update Entry
    // =========================================================================

    /// Mark a notebook entry (to-do) as complete.
    public func completeEntry(entryId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE notebook_entries
                    SET task_status = 'complete', updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [entryId]
            )
        }
    }

    // MARK: - 7. Notebooks Stats
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
    // MARK: - Work Classification (Warranty)
    // =========================================================================

    /// A record of a classification change for audit trail.
    public struct ClassificationChange: Sendable, Identifiable {
        public let id: Int64
        public let entryId: Int64
        public let oldClassification: String?
        public let newClassification: String
        public let changedBy: Int64
        public let reason: String?
        public let changedAt: String

        public init(id: Int64, entryId: Int64, oldClassification: String?,
                    newClassification: String, changedBy: Int64,
                    reason: String?, changedAt: String) {
            self.id = id
            self.entryId = entryId
            self.oldClassification = oldClassification
            self.newClassification = newClassification
            self.changedBy = changedBy
            self.reason = reason
            self.changedAt = changedAt
        }
    }

    private enum ClassificationPermission {
        static let classify = "notebooks.classify_todo"
        static let reclassify = "notebooks.reclassify_todo"
        static let review = "notebooks.review_classification"
    }

    private func requirePermission(userId: Int64, permissionKey: String) throws {
        guard try auth.hasPermission(userId, permissionKey: permissionKey) else {
            throw NotebooksError.insufficientPermissions(required: permissionKey)
        }
    }

    private static func fetchActiveClassification(_ dbConn: Database, entryId: Int64) throws -> String? {
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT work_classification
            FROM notebook_entries
            WHERE id = ? AND deleted_at IS NULL
            """, arguments: [entryId])
        guard let row else { throw NotebooksError.entryNotFound(entryId) }
        return row["work_classification"] as String?
    }

    /// Classify a to-do as regular or warranty work.
    public func classifyTodoWork(entryId: Int64, classification: String, classifiedBy: Int64) throws {
        try requirePermission(userId: classifiedBy, permissionKey: ClassificationPermission.classify)
        try db.writer.write { dbConn in
            let current = try Self.fetchActiveClassification(dbConn, entryId: entryId)

            try dbConn.execute(sql: """
                UPDATE notebook_entries SET
                    work_classification = ?,
                    classification_reviewed = 0,
                    classification_reviewed_by = NULL,
                    classification_reviewed_at = NULL,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [classification, entryId])

            try dbConn.execute(sql: """
                INSERT INTO classification_history
                    (entry_id, old_classification, new_classification, changed_by, changed_at)
                VALUES (?, ?, ?, ?, datetime('now'))
                """, arguments: [entryId, current, classification, classifiedBy])
        }
    }

    /// Manager reviews/approves a classification.
    public func reviewClassification(entryId: Int64, reviewedBy: Int64, approved: Bool, newClassification: String?) throws {
        try requirePermission(userId: reviewedBy, permissionKey: ClassificationPermission.review)
        try db.writer.write { dbConn in
            let current = try Self.fetchActiveClassification(dbConn, entryId: entryId)

            if approved {
                try dbConn.execute(sql: """
                    UPDATE notebook_entries SET
                        classification_reviewed = 1,
                        classification_reviewed_by = ?,
                        classification_reviewed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [reviewedBy, entryId])
            } else if let newClass = newClassification {
                try dbConn.execute(sql: """
                    UPDATE notebook_entries SET
                        work_classification = ?,
                        classification_reviewed = 1,
                        classification_reviewed_by = ?,
                        classification_reviewed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [newClass, reviewedBy, entryId])

                try dbConn.execute(sql: """
                    INSERT INTO classification_history
                        (entry_id, old_classification, new_classification, changed_by, reason, changed_at)
                    VALUES (?, ?, ?, ?, 'Manager review', datetime('now'))
                    """, arguments: [entryId, current, newClass, reviewedBy])
            }
        }
    }

    /// List all pending warranty classification reviews across job notebooks.
    public func listPendingWarrantyClassifications() throws -> [PendingWarrantyClassification] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ne.id,
                           COALESCE(ne.title, '') AS title,
                           COALESCE(ne.content, '') AS content,
                           COALESCE(ne.work_classification, '') AS work_classification,
                           COALESCE(ne.updated_at, ne.created_at, '') AS created_at,
                           COALESCE(u.display_name, u.email, 'Unknown') AS requested_by_name,
                           COALESCE(j.job_name, n.title, 'Unknown Job') AS job_name
                    FROM notebook_entries ne
                    INNER JOIN notebook_sections ns ON ns.id = ne.section_id
                    INNER JOIN notebooks n ON n.id = ns.notebook_id
                    LEFT JOIN jobs j ON j.id = n.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = ne.created_by AND u.deleted_at IS NULL
                    WHERE ne.deleted_at IS NULL
                      AND n.deleted_at IS NULL
                      AND ne.work_classification IS NOT NULL
                      AND COALESCE(ne.classification_reviewed, 0) = 0
                    ORDER BY COALESCE(ne.updated_at, ne.created_at) ASC, ne.id ASC
                    """)
                return rows.map { row in
                    PendingWarrantyClassification(
                        id: row["id"] ?? 0,
                        entryTitle: row["title"] ?? "",
                        entryContent: row["content"] ?? "",
                        requestedClassification: row["work_classification"] ?? "",
                        requestedByName: row["requested_by_name"] ?? "Unknown",
                        jobName: row["job_name"] ?? "Unknown Job",
                        createdAt: row["created_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Reclassify a to-do with reason tracking. Resets the review flag.
    public func reclassifyTodoWork(entryId: Int64, newClassification: String, changedBy: Int64, reason: String?) throws {
        try requirePermission(userId: changedBy, permissionKey: ClassificationPermission.reclassify)
        try db.writer.write { dbConn in
            let current = try Self.fetchActiveClassification(dbConn, entryId: entryId)

            try dbConn.execute(sql: """
                UPDATE notebook_entries SET
                    work_classification = ?,
                    classification_reviewed = 0,
                    classification_reviewed_by = NULL,
                    classification_reviewed_at = NULL,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [newClassification, entryId])

            try dbConn.execute(sql: """
                INSERT INTO classification_history
                    (entry_id, old_classification, new_classification, changed_by, reason, changed_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [entryId, current, newClassification, changedBy, reason])
        }
    }

    /// Get classification history for a to-do.
    public func getClassificationHistory(entryId: Int64) throws -> [ClassificationChange] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, entry_id, old_classification, new_classification,
                       changed_by, reason, changed_at
                FROM classification_history
                WHERE entry_id = ?
                ORDER BY changed_at DESC
                """, arguments: [entryId])
            return rows.map { row in
                ClassificationChange(
                    id: row["id"] ?? 0,
                    entryId: row["entry_id"] ?? 0,
                    oldClassification: row["old_classification"] as String?,
                    newClassification: row["new_classification"] ?? "",
                    changedBy: row["changed_by"] ?? 0,
                    reason: row["reason"] as String?,
                    changedAt: row["changed_at"] ?? ""
                )
            }
        }
    }

    /// Start warranty timer when a to-do is completed. Sets timer_start = now, timer_end = now + job warranty days.
    public func startWarrantyTimer(entryId: Int64, warrantyDurationDays: Int) throws {
        guard warrantyDurationDays > 0 else {
            throw NotebooksError.invalidDuration(entryId)
        }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: warrantyDurationDays, to: now) ?? now.addingTimeInterval(Double(warrantyDurationDays) * 86400)
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_entries SET
                    warranty_timer_start = ?,
                    warranty_timer_end = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [CoreFormatters.iso8601.string(from: now), CoreFormatters.iso8601.string(from: end), entryId])
        }
    }

    /// Get to-dos needing classification review for a job (classified but not yet reviewed by manager).
    public func getTodosNeedingReview(jobId: Int64) throws -> [NotebookEntryRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT ne.id, ne.entry_type, ne.title, ne.content, ne.sort_order,
                           COALESCE(ne.is_completed, 0) as is_completed, ne.created_at,
                           ne.block_type, ne.block_data, ne.heading_level, ne.checklist_items,
                           ne.photo_path, ne.reference_type, ne.reference_id,
                           ne.work_classification, COALESCE(ne.classification_reviewed, 0) as classification_reviewed,
                           ne.warranty_timer_end, COALESCE(ne.is_question, 0) as is_question,
                           COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name
                    FROM notebook_entries ne
                    LEFT JOIN users u ON u.id = ne.created_by AND u.deleted_at IS NULL
                    INNER JOIN notebooks n ON n.id = ne.notebook_id
                    WHERE n.job_id = ? AND n.deleted_at IS NULL
                          AND ne.deleted_at IS NULL
                          AND ne.work_classification IS NOT NULL
                          AND ne.classification_reviewed = 0
                    ORDER BY ne.updated_at DESC
                    """, arguments: [jobId])
                return rows.map { row in
                    NotebookEntryRow(
                        id: row["id"] ?? 0,
                        entryType: row["entry_type"] ?? "todo",
                        content: row["content"] ?? "",
                        createdByName: row["created_by_name"] ?? "Unknown",
                        sortOrder: row["sort_order"] ?? 0,
                        isCompleted: (row["is_completed"] as Int?) == 1,
                        createdAt: row["created_at"] as String?,
                        title: row["title"] as String?,
                        blockType: row["block_type"] ?? "text",
                        blockData: row["block_data"] as String?,
                        headingLevel: row["heading_level"] as Int?,
                        checklistItems: row["checklist_items"] as String?,
                        photoPath: row["photo_path"] as String?,
                        referenceType: row["reference_type"] as String?,
                        referenceId: row["reference_id"] as Int64?,
                        workClassification: row["work_classification"] as String?,
                        classificationReviewed: (row["classification_reviewed"] as Int?) == 1,
                        warrantyTimerEnd: row["warranty_timer_end"] as String?,
                        isQuestion: (row["is_question"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Ensure a "Warranty Work" section group exists in a notebook. Creates if missing.
    @discardableResult
    public func ensureWarrantySection(notebookId: Int64) throws -> Int64 {
        try db.writer.write { dbConn in
            // Check if "Warranty Work" group already exists
            if let existingId = try Int64.fetchOne(dbConn, sql: """
                SELECT id FROM notebook_section_groups
                WHERE notebook_id = ? AND name = 'Warranty Work' AND deleted_at IS NULL
                """, arguments: [notebookId]) {
                return existingId
            }

            // Create it
            let maxOrder = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(MAX(sort_order), -1) FROM notebook_section_groups
                WHERE notebook_id = ? AND deleted_at IS NULL
                """, arguments: [notebookId]) ?? -1

            try dbConn.execute(sql: """
                INSERT INTO notebook_section_groups (notebook_id, name, sort_order, created_at, updated_at)
                VALUES (?, 'Warranty Work', ?, datetime('now'), datetime('now'))
                """, arguments: [notebookId, maxOrder + 1])
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - Section Groups
    // =========================================================================

    /// Create a new section group in a notebook.
    @discardableResult
    public func createSectionGroup(notebookId: Int64, name: String) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
            let maxOrder = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(MAX(sort_order), -1) FROM notebook_section_groups
                WHERE notebook_id = ? AND deleted_at IS NULL
                """, arguments: [notebookId]) ?? -1

            try dbConn.execute(sql: """
                INSERT INTO notebook_section_groups (notebook_id, name, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, datetime('now'), datetime('now'))
                """, arguments: [notebookId, name, maxOrder + 1])
            return dbConn.lastInsertedRowID
        }
    }

    /// Update a section group's name.
    public func updateSectionGroup(groupId: Int64, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_section_groups SET name = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [name, groupId])
        }
    }

    /// Soft-delete a section group.
    public func deleteSectionGroup(groupId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_section_groups SET deleted_at = datetime('now')
                WHERE id = ?
                """, arguments: [groupId])
            // Unlink sections from this group (they become ungrouped)
            try dbConn.execute(sql: """
                UPDATE notebook_sections SET group_id = NULL, updated_at = datetime('now')
                WHERE group_id = ?
                """, arguments: [groupId])
        }
    }

    /// Reorder section groups within a notebook.
    public func reorderSectionGroups(notebookId: Int64, orderedIds: [Int64]) throws {
        try db.writer.write { dbConn in
            for (index, groupId) in orderedIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE notebook_section_groups SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ? AND notebook_id = ? AND deleted_at IS NULL
                    """, arguments: [index, groupId, notebookId])
            }
        }
    }

    // =========================================================================
    // MARK: - Sections (Extended)
    // =========================================================================

    /// Create a new section in a notebook, optionally within a group.
    @discardableResult
    public func createSection(notebookId: Int64, groupId: Int64?, name: String) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
            let maxOrder = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(MAX(sort_order), -1) FROM notebook_sections
                WHERE notebook_id = ? AND deleted_at IS NULL
                """, arguments: [notebookId]) ?? -1

            try dbConn.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, group_id, name, section_type, sort_order, is_locked, is_collapsed, created_at, updated_at)
                VALUES (?, ?, ?, 'notes', ?, 0, 0, datetime('now'), datetime('now'))
                """, arguments: [notebookId, groupId, name, maxOrder + 1])
            return dbConn.lastInsertedRowID
        }
    }

    /// Update a section's name.
    public func updateSection(sectionId: Int64, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_sections SET name = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [name, sectionId])
        }
    }

    /// Soft-delete a section.
    public func deleteSection(sectionId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_sections SET deleted_at = datetime('now')
                WHERE id = ?
                """, arguments: [sectionId])
        }
    }

    /// Move a section to a different group (or ungrouped if nil).
    public func moveSection(sectionId: Int64, toGroupId: Int64?, sortOrder: Int) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_sections SET group_id = ?, sort_order = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [toGroupId, sortOrder, sectionId])
        }
    }

    /// Reorder sections within a group.
    public func reorderSections(groupId: Int64?, orderedIds: [Int64]) throws {
        try db.writer.write { dbConn in
            for (index, sectionId) in orderedIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE notebook_sections SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [index, sectionId])
            }
        }
    }

    // =========================================================================
    // MARK: - Block Entries
    // =========================================================================

    /// Create a block entry in a section.
    @discardableResult
    public func createBlockEntry(
        sectionId: Int64,
        blockType: String = "text",
        title: String? = nil,
        content: String? = nil,
        blockData: String? = nil,
        createdBy: Int64,
        sortOrder: Int? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            let order: Int
            if let so = sortOrder {
                order = so
            } else {
                order = (try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(MAX(sort_order), -1) FROM notebook_entries
                    WHERE section_id = ? AND deleted_at IS NULL
                    """, arguments: [sectionId]) ?? -1) + 1
            }

            let notebookId = try Int64.fetchOne(dbConn, sql: """
                SELECT notebook_id FROM notebook_sections WHERE id = ?
                """, arguments: [sectionId])

            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                (section_id, notebook_id, title, content, entry_type, block_type, block_data,
                 field_required, is_deleted, is_completed, sort_order, created_by, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'note', ?, ?, 0, 0, 0, ?, ?, datetime('now'), datetime('now'))
                """, arguments: [sectionId, notebookId, title ?? "", content, blockType, blockData, order, createdBy])
            return dbConn.lastInsertedRowID
        }
    }

    /// Update a block entry's content and/or block data.
    public func updateBlockEntry(entryId: Int64, content: String?, blockData: String?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_entries SET content = ?, block_data = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [content, blockData, entryId])
        }
    }

    /// Soft-delete a block entry.
    public func deleteBlockEntry(entryId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_entries SET deleted_at = datetime('now'), is_deleted = 1
                WHERE id = ?
                """, arguments: [entryId])
        }
    }

    /// Reorder block entries within a section.
    public func reorderBlockEntries(sectionId: Int64, orderedIds: [Int64]) throws {
        try db.writer.write { dbConn in
            for (index, entryId) in orderedIds.enumerated() {
                try dbConn.execute(sql: """
                    UPDATE notebook_entries SET sort_order = ?, updated_at = datetime('now')
                    WHERE id = ? AND section_id = ? AND deleted_at IS NULL
                    """, arguments: [index, entryId, sectionId])
            }
        }
    }

    // =========================================================================
    // MARK: - Hierarchy Queries
    // =========================================================================

    /// Full hierarchy structure for a notebook.
    public struct NotebookHierarchy: Sendable {
        public let groups: [SectionGroupWithChildren]
        public let ungroupedSections: [SectionWithEntries]
    }

    /// A section group with its child sections and entries.
    public struct SectionGroupWithChildren: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let sortOrder: Int
        public let isCollapsed: Bool
        public let sections: [SectionWithEntries]
    }

    /// A section with its entries.
    public struct SectionWithEntries: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let groupId: Int64?
        public let sortOrder: Int
        public let isCollapsed: Bool
        public let entries: [NotebookEntryRow]
    }

    /// Get full notebook hierarchy: groups → sections → entries.
    public func getNotebookHierarchy(notebookId: Int64) throws -> NotebookHierarchy {
        do {
            return try db.writer.read { dbConn in
                // 1. Get all section groups
                let groupRows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, name, sort_order, is_collapsed
                    FROM notebook_section_groups
                    WHERE notebook_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order ASC
                    """, arguments: [notebookId])

                // 2. Get all sections
                let sectionRows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, name, group_id, sort_order, COALESCE(is_collapsed, 0) as is_collapsed
                    FROM notebook_sections
                    WHERE notebook_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order ASC
                    """, arguments: [notebookId])

                // 3. Get all entries
                let entryRows = try Row.fetchAll(dbConn, sql: """
                    SELECT ne.id, ne.section_id, ne.entry_type, ne.title, ne.content, ne.sort_order,
                           COALESCE(ne.is_completed, 0) as is_completed, ne.created_at,
                           ne.block_type, ne.block_data, ne.heading_level, ne.checklist_items,
                           ne.photo_path, ne.reference_type, ne.reference_id,
                           ne.work_classification, COALESCE(ne.classification_reviewed, 0) as classification_reviewed,
                           ne.warranty_timer_end, COALESCE(ne.is_question, 0) as is_question,
                           COALESCE(u.display_name, u.email, 'Unknown') AS created_by_name
                    FROM notebook_entries ne
                    LEFT JOIN users u ON u.id = ne.created_by AND u.deleted_at IS NULL
                    WHERE ne.section_id IN (SELECT id FROM notebook_sections WHERE notebook_id = ? AND deleted_at IS NULL)
                      AND ne.deleted_at IS NULL AND ne.is_deleted = 0
                    ORDER BY ne.sort_order ASC, ne.created_at ASC
                    """, arguments: [notebookId])

                // Map entries by section ID
                var entriesBySectionId: [Int64: [NotebookEntryRow]] = [:]
                for row in entryRows {
                    let sectionId: Int64 = row["section_id"] ?? 0
                    let entry = NotebookEntryRow(
                        id: row["id"] ?? 0,
                        entryType: row["entry_type"] ?? "note",
                        content: row["content"] ?? "",
                        createdByName: row["created_by_name"] ?? "Unknown",
                        sortOrder: row["sort_order"] ?? 0,
                        isCompleted: (row["is_completed"] as Int?) == 1,
                        createdAt: row["created_at"],
                        title: row["title"] as String?,
                        blockType: row["block_type"] ?? "text",
                        blockData: row["block_data"] as String?,
                        headingLevel: row["heading_level"] as Int?,
                        checklistItems: row["checklist_items"] as String?,
                        photoPath: row["photo_path"] as String?,
                        referenceType: row["reference_type"] as String?,
                        referenceId: row["reference_id"] as Int64?,
                        workClassification: row["work_classification"] as String?,
                        classificationReviewed: (row["classification_reviewed"] as Int?) == 1,
                        warrantyTimerEnd: row["warranty_timer_end"] as String?,
                        isQuestion: (row["is_question"] as Int?) == 1
                    )
                    entriesBySectionId[sectionId, default: []].append(entry)
                }

                // Build sections
                func buildSection(_ row: Row) -> SectionWithEntries {
                    let sid: Int64 = row["id"] ?? 0
                    return SectionWithEntries(
                        id: sid,
                        name: row["name"] ?? "",
                        groupId: row["group_id"],
                        sortOrder: row["sort_order"] ?? 0,
                        isCollapsed: (row["is_collapsed"] as Int?) == 1,
                        entries: entriesBySectionId[sid] ?? []
                    )
                }

                // Build groups with their sections
                var usedSectionIds = Set<Int64>()
                let groups: [SectionGroupWithChildren] = groupRows.map { gRow in
                    let gid: Int64 = gRow["id"] ?? 0
                    let childSections = sectionRows.filter { ($0["group_id"] as Int64?) == gid }
                        .map { row -> SectionWithEntries in
                            let s = buildSection(row)
                            usedSectionIds.insert(s.id)
                            return s
                        }
                    return SectionGroupWithChildren(
                        id: gid,
                        name: gRow["name"] ?? "",
                        sortOrder: gRow["sort_order"] ?? 0,
                        isCollapsed: (gRow["is_collapsed"] as Int?) == 1,
                        sections: childSections
                    )
                }

                // Ungrouped sections
                let ungrouped = sectionRows
                    .filter { ($0["group_id"] as Int64?) == nil }
                    .map { buildSection($0) }

                return NotebookHierarchy(groups: groups, ungroupedSections: ungrouped)
            }
        } catch {
            if isTableNotFoundError(error) {
                return NotebookHierarchy(groups: [], ungroupedSections: [])
            }
            throw error
        }
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

    // =========================================================================
    // MARK: - Templates
    // =========================================================================

    /// Template data structure for JSON encoding/decoding.
    public struct NotebookTemplateData: Codable, Sendable {
        public let groups: [TemplateGroup]

        public struct TemplateGroup: Codable, Sendable {
            public let name: String
            public let sections: [TemplateSection]
        }

        public struct TemplateSection: Codable, Sendable {
            public let name: String
            public let entries: [TemplateEntry]
        }

        public struct TemplateEntry: Codable, Sendable {
            public let blockType: String
            public let title: String?
            public let content: String?
            public let headingLevel: Int?
            public let checklistItems: [[String: String]]?
        }
    }

    /// Template list item for display.
    public struct NotebookTemplateItem: Identifiable, Sendable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let templateType: String
        public let category: String?
        public let isDefault: Bool
        public let createdAt: String?
    }

    /// Get all templates, optionally filtered by type.
    public func getTemplates(templateType: String? = nil) throws -> [NotebookTemplateItem] {
        do {
            return try db.writer.read { dbConn in
                var sql = """
                    SELECT id, name, description, template_type, category, is_default, created_at
                    FROM notebook_templates
                    WHERE deleted_at IS NULL
                    """
                var args: [any DatabaseValueConvertible] = []
                if let tt = templateType {
                    sql += " AND template_type = ?"
                    args.append(tt)
                }
                sql += " ORDER BY is_default DESC, name ASC"
                return try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)).map { row in
                    NotebookTemplateItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        templateType: row["template_type"] ?? "job",
                        category: row["category"] as String?,
                        isDefault: (row["is_default"] as Int?) == 1,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a template.
    public func createTemplate(
        name: String,
        description: String?,
        templateType: String,
        category: String?,
        templateData: NotebookTemplateData,
        createdBy: Int64
    ) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NotebooksError.requiredFieldEmpty
        }
        let jsonData = try JSONEncoder().encode(templateData)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_templates (name, description, template_type, category, template_data, created_by)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [name, description, templateType, category, jsonString, createdBy])
            return dbConn.lastInsertedRowID
        }
    }

    /// Apply a job template to a notebook — creates groups, sections, and entries.
    public func applyJobTemplate(templateId: Int64, notebookId: Int64, createdBy: Int64) throws {
        let templateRow = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT template_data FROM notebook_templates WHERE id = ?", arguments: [templateId])
        }
        guard let jsonString = templateRow?["template_data"] as String?,
              let jsonData = jsonString.data(using: .utf8) else { return }

        let template = try JSONDecoder().decode(NotebookTemplateData.self, from: jsonData)

        // Single transaction — partial template application is worse than no application.
        try db.writer.write { dbConn in
            for group in template.groups {
                let groupMaxOrder = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(MAX(sort_order), -1) FROM notebook_section_groups
                    WHERE notebook_id = ? AND deleted_at IS NULL
                    """, arguments: [notebookId]) ?? -1
                try dbConn.execute(sql: """
                    INSERT INTO notebook_section_groups (notebook_id, name, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, datetime('now'), datetime('now'))
                    """, arguments: [notebookId, group.name, groupMaxOrder + 1])
                let groupId = dbConn.lastInsertedRowID

                for section in group.sections {
                    let sectionMaxOrder = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(MAX(sort_order), -1) FROM notebook_sections
                        WHERE notebook_id = ? AND deleted_at IS NULL
                        """, arguments: [notebookId]) ?? -1
                    try dbConn.execute(sql: """
                        INSERT INTO notebook_sections (notebook_id, group_id, name, section_type, sort_order, is_locked, is_collapsed, created_at, updated_at)
                        VALUES (?, ?, ?, 'standard', ?, 0, 0, datetime('now'), datetime('now'))
                        """, arguments: [notebookId, groupId, section.name, sectionMaxOrder + 1])
                    let sectionId = dbConn.lastInsertedRowID

                    for (entryIndex, entry) in section.entries.enumerated() {
                        var checklistJson: String? = nil
                        if let items = entry.checklistItems, let data = try? JSONSerialization.data(withJSONObject: items) {
                            checklistJson = String(data: data, encoding: .utf8)
                        }
                        try dbConn.execute(sql: """
                            INSERT INTO notebook_entries (notebook_id, section_id, entry_type, block_type, title, content,
                                heading_level, checklist_items, sort_order, created_by, created_at)
                            VALUES (?, ?, 'note', ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                            """, arguments: [
                                notebookId, sectionId, entry.blockType,
                                entry.title, entry.content,
                                entry.headingLevel, checklistJson,
                                entryIndex, createdBy
                            ])
                    }
                }
            }
        }
    }

    /// Apply a page template to a section — creates entries.
    public func applyPageTemplate(templateId: Int64, sectionId: Int64, createdBy: Int64) throws {
        let templateRow = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT template_data FROM notebook_templates WHERE id = ?", arguments: [templateId])
        }
        guard let jsonString = templateRow?["template_data"] as String?,
              let jsonData = jsonString.data(using: .utf8) else { return }

        let template = try JSONDecoder().decode(NotebookTemplateData.self, from: jsonData)

        // Page templates use the first section's entries from the first group
        guard let firstGroup = template.groups.first,
              let firstSection = firstGroup.sections.first else { return }

        // Single transaction — partial template application is worse than no application.
        try db.writer.write { dbConn in
            let notebookId = try Int64.fetchOne(dbConn, sql: """
                SELECT notebook_id FROM notebook_sections WHERE id = ?
                """, arguments: [sectionId])
            for (idx, entry) in firstSection.entries.enumerated() {
                let checklistJson: String? = entry.checklistItems.flatMap { items in
                    (try? JSONSerialization.data(withJSONObject: items)).flatMap { String(data: $0, encoding: .utf8) }
                }
                try dbConn.execute(sql: """
                    INSERT INTO notebook_entries
                    (section_id, notebook_id, title, content, entry_type, block_type, checklist_items,
                     field_required, is_deleted, is_completed, sort_order, created_by, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'note', ?, ?, 0, 0, 0, ?, ?, datetime('now'), datetime('now'))
                    """, arguments: [sectionId, notebookId, entry.title ?? "", entry.content, entry.blockType, checklistJson, idx, createdBy])
            }
        }
    }

    /// Delete a template (soft delete).
    public func deleteTemplate(templateId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE notebook_templates SET deleted_at = datetime('now') WHERE id = ?
                """, arguments: [templateId])
        }
    }

    /// Seed default templates if none exist.
    public func seedDefaultTemplates(createdBy: Int64) throws {
        let count = try db.writer.read { dbConn -> Int in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM notebook_templates WHERE is_default = 1") ?? 0
        }
        guard count == 0 else { return }

        // Residential Job Template
        let residentialTemplate = NotebookTemplateData(groups: [
            .init(name: "Safety & Compliance", sections: [
                .init(name: "Safety Checklist", entries: [
                    .init(blockType: "heading", title: "Pre-Work Safety", content: nil, headingLevel: 1, checklistItems: nil),
                    .init(blockType: "checklist", title: "Safety Items", content: nil, headingLevel: nil, checklistItems: [
                        ["text": "PPE verified", "checked": "false"],
                        ["text": "Area secured", "checked": "false"],
                        ["text": "Permits posted", "checked": "false"],
                        ["text": "Fire extinguisher accessible", "checked": "false"],
                    ]),
                ]),
            ]),
            .init(name: "Materials & Parts", sections: [
                .init(name: "Material List", entries: []),
                .init(name: "Parts Used", entries: []),
            ]),
            .init(name: "Daily Log", sections: [
                .init(name: "Day 1", entries: [
                    .init(blockType: "heading", title: "Daily Log", content: nil, headingLevel: 1, checklistItems: nil),
                    .init(blockType: "text", title: "Notes", content: "", headingLevel: nil, checklistItems: nil),
                ]),
            ]),
            .init(name: "Photos", sections: [
                .init(name: "Progress Photos", entries: []),
                .init(name: "Issue Photos", entries: []),
            ]),
            .init(name: "Punch List", sections: [
                .init(name: "Items", entries: []),
            ]),
        ])

        let jsonData = try JSONEncoder().encode(residentialTemplate)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_templates (name, description, template_type, category, template_data, is_default, created_by)
                VALUES (?, ?, ?, ?, ?, 1, ?)
                """, arguments: [
                    "Residential Job", "Standard residential job notebook with safety, materials, daily log, photos, and punch list",
                    "job", "residential", jsonString, createdBy
                ])
        }

        // Commercial Job Template
        let commercialTemplate = NotebookTemplateData(groups: [
            .init(name: "Safety & Compliance", sections: [
                .init(name: "Safety Checklist", entries: [
                    .init(blockType: "checklist", title: "Daily Safety", content: nil, headingLevel: nil, checklistItems: [
                        ["text": "PPE verified", "checked": "false"],
                        ["text": "Area secured", "checked": "false"],
                        ["text": "OSHA signage posted", "checked": "false"],
                        ["text": "Fire watch assigned", "checked": "false"],
                    ]),
                ]),
                .init(name: "Permits", entries: []),
            ]),
            .init(name: "Panel Schedules", sections: [
                .init(name: "Main Panel", entries: []),
            ]),
            .init(name: "Materials & Parts", sections: [
                .init(name: "Material List", entries: []),
                .init(name: "Parts Used", entries: []),
                .init(name: "Returns", entries: []),
            ]),
            .init(name: "Daily Log", sections: []),
            .init(name: "Photos & Documentation", sections: [
                .init(name: "Progress Photos", entries: []),
                .init(name: "As-Built Photos", entries: []),
                .init(name: "Issue Photos", entries: []),
            ]),
            .init(name: "Punch List", sections: [
                .init(name: "Items", entries: []),
            ]),
        ])

        let commercialJson = try JSONEncoder().encode(commercialTemplate)
        let commercialJsonStr = String(data: commercialJson, encoding: .utf8) ?? "{}"

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_templates (name, description, template_type, category, template_data, is_default, created_by)
                VALUES (?, ?, ?, ?, ?, 1, ?)
                """, arguments: [
                    "Commercial Job", "Commercial job notebook with panel schedules, permits, and as-built documentation",
                    "job", "commercial", commercialJsonStr, createdBy
                ])
        }

        // Service Call Template
        let serviceTemplate = NotebookTemplateData(groups: [
            .init(name: "Service Call", sections: [
                .init(name: "Problem Description", entries: [
                    .init(blockType: "text", title: "Customer Complaint", content: "", headingLevel: nil, checklistItems: nil),
                ]),
                .init(name: "Diagnosis", entries: []),
                .init(name: "Work Performed", entries: []),
                .init(name: "Parts Used", entries: []),
                .init(name: "Photos", entries: []),
            ]),
        ])

        let serviceJson = try JSONEncoder().encode(serviceTemplate)
        let serviceJsonStr = String(data: serviceJson, encoding: .utf8) ?? "{}"

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_templates (name, description, template_type, category, template_data, is_default, created_by)
                VALUES (?, ?, ?, ?, ?, 1, ?)
                """, arguments: [
                    "Service Call", "Quick service call notebook for diagnosis and repair",
                    "job", "service", serviceJsonStr, createdBy
                ])
        }
    }

    // =========================================================================
    // MARK: - Block Conflict Detection & Resolution
    // =========================================================================

    /// Detect unreviewed sync conflicts on notebook entry blocks for a specific notebook.
    ///
    /// Queries `_conflict_log` for rows where:
    /// - `table_name = 'notebook_entries'`
    /// - `record_id` matches an entry in this notebook
    /// - `reviewed = 0` (not yet resolved by the user)
    ///
    /// Returns conflicts joined with entry metadata so the UI can show context
    /// (entry title, block type) alongside the conflicting values.
    public func detectBlockConflicts(notebookId: Int64) throws -> [NotebookBlockConflict] {
        do {
            return try db.writer.read { dbConn -> [NotebookBlockConflict] in
                let sql = """
                    SELECT cl.id AS conflict_id,
                           cl.record_id,
                           cl.field_name,
                           cl.local_value,
                           cl.remote_value,
                           cl.local_ts,
                           cl.remote_ts,
                           cl.local_device,
                           cl.remote_device,
                           cl.winner,
                           cl.resolved_at,
                           ne.title AS entry_title,
                           ne.block_type
                    FROM _conflict_log cl
                    INNER JOIN notebook_entries ne ON CAST(cl.record_id AS INTEGER) = ne.id
                    WHERE cl.table_name = 'notebook_entries'
                      AND cl.reviewed = 0
                      AND ne.notebook_id = ?
                    ORDER BY cl.resolved_at DESC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [notebookId])
                return rows.map { row in
                    NotebookBlockConflict(
                        conflictLogId: row["conflict_id"] ?? 0,
                        entryId: Int64(row["record_id"] as String? ?? "0") ?? 0,
                        fieldName: row["field_name"] ?? "",
                        localValue: row["local_value"] as String?,
                        remoteValue: row["remote_value"] as String?,
                        localTimestamp: row["local_ts"] ?? "",
                        remoteTimestamp: row["remote_ts"] ?? "",
                        localDeviceId: row["local_device"] ?? "",
                        remoteDeviceId: row["remote_device"] ?? "",
                        winner: row["winner"] ?? "local",
                        resolvedAt: row["resolved_at"] as String?,
                        entryTitle: row["entry_title"] as String?,
                        blockType: row["block_type"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Resolve a notebook block conflict by applying the user's chosen version.
    ///
    /// - Parameters:
    ///   - conflictLogId: The `_conflict_log.id` of the conflict to resolve.
    ///   - keepVersion: `"local"` or `"remote"` — which side's value to keep.
    ///
    /// If the user picks the version that LWW already chose (i.e., the `winner`
    /// column matches `keepVersion`), we just mark it reviewed. If the user
    /// overrides the LWW decision, we update the entry field to the non-winning
    /// value and then mark it reviewed.
    public func resolveBlockConflict(conflictLogId: Int64, keepVersion: String) throws {
        try db.writer.write { dbConn in
            // 1. Read the conflict record
            guard let conflictRow = try Row.fetchOne(dbConn, sql: """
                SELECT record_id, field_name, local_value, remote_value, winner
                FROM _conflict_log WHERE id = ?
                """, arguments: [conflictLogId]) else {
                return
            }

            let recordId: String = conflictRow["record_id"] ?? "0"
            let fieldName: String = conflictRow["field_name"] ?? ""
            let localValue: String? = conflictRow["local_value"]
            let remoteValue: String? = conflictRow["remote_value"]
            let currentWinner: String = conflictRow["winner"] ?? "local"

            // 2. If user chose the opposite of what LWW picked, apply the override
            if keepVersion != currentWinner {
                let valueToApply = (keepVersion == "local") ? localValue : remoteValue

                // Only update content-related fields to prevent schema issues.
                // Use a literal-backed map so the SQL column name is never a runtime variable.
                let allowedFields: [String: String] = [
                    "content": "content",
                    "block_data": "block_data",
                    "title": "title",
                    "checklist_items": "checklist_items",
                    "heading_level": "heading_level",
                    "photo_path": "photo_path",
                    "task_status": "task_status",
                    "sort_order": "sort_order"
                ]

                if let safeColumn = allowedFields[fieldName] {
                    try dbConn.execute(
                        sql: "UPDATE notebook_entries SET \"\(safeColumn)\" = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [valueToApply, recordId]
                    )
                }
            }

            // 3. Mark the conflict as reviewed
            try dbConn.execute(
                sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ?",
                arguments: [conflictLogId]
            )
        }
    }

    /// Bulk-resolve all unreviewed conflicts for a notebook, keeping the specified version.
    ///
    /// Convenience method for "Keep All Local" or "Keep All Remote" actions.
    public func resolveAllBlockConflicts(notebookId: Int64, keepVersion: String) throws {
        let conflicts = try detectBlockConflicts(notebookId: notebookId)
        for conflict in conflicts {
            try resolveBlockConflict(conflictLogId: conflict.conflictLogId, keepVersion: keepVersion)
        }
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
