import Foundation
import GRDB

extension JobsService {
    /// Local-first job record used by job-detail flows and future sync paths.
    /// `stableId` is generated locally and survives reloads/sync reconciliation,
    /// while `id` remains the SQLite row id for local joins.
    public struct JobRecord: Sendable, Identifiable, Equatable {
        public let id: Int64
        public let stableId: String
        public let jobNumber: String
        public let jobName: String
        public let customerName: String?
        public let siteName: String?
        public let status: String
        public let priority: String
        public let jobType: String
        public let notes: String?
        public let createdAt: String?
        public let updatedAt: String?
    }

    public struct JobRecordDraft: Sendable, Equatable {
        public let jobNumber: String
        public let jobName: String
        public let customerName: String?
        public let siteName: String?
        public let status: String
        public let priority: String
        public let jobType: String
        public let notes: String?
        public let createdBy: Int64?

        public init(
            jobNumber: String,
            jobName: String,
            customerName: String? = nil,
            siteName: String? = nil,
            status: String = "active",
            priority: String = "normal",
            jobType: String = "service",
            notes: String? = nil,
            createdBy: Int64? = nil
        ) {
            self.jobNumber = jobNumber
            self.jobName = jobName
            self.customerName = customerName
            self.siteName = siteName
            self.status = status
            self.priority = priority
            self.jobType = jobType
            self.notes = notes
            self.createdBy = createdBy
        }
    }

    public struct JobRecordUpdate: Sendable, Equatable {
        public let jobName: String?
        public let customerName: String?
        public let siteName: String?
        public let status: String?
        public let priority: String?
        public let jobType: String?
        public let notes: String?

        public init(
            jobName: String? = nil,
            customerName: String? = nil,
            siteName: String? = nil,
            status: String? = nil,
            priority: String? = nil,
            jobType: String? = nil,
            notes: String? = nil
        ) {
            self.jobName = jobName
            self.customerName = customerName
            self.siteName = siteName
            self.status = status
            self.priority = priority
            self.jobType = jobType
            self.notes = notes
        }
    }

    @discardableResult
    public func createJobRecord(_ draft: JobRecordDraft) throws -> JobRecord {
        let jobNumber = try Self.requiredTrimmed(draft.jobNumber)
        let jobName = try Self.requiredTrimmed(draft.jobName)
        let status = try Self.requiredTrimmed(draft.status)
        let priority = try Self.requiredTrimmed(draft.priority)
        let jobType = try Self.requiredTrimmed(draft.jobType)
        let customerName = Self.optionalTrimmed(draft.customerName)
        let siteName = Self.optionalTrimmed(draft.siteName)
        let notes = Self.optionalTrimmed(draft.notes)

        let jobId = try createJob(
            jobNumber: jobNumber,
            jobName: jobName,
            customerName: customerName,
            addressLine1: siteName,
            status: status,
            priority: priority,
            jobType: jobType,
            notes: notes,
            createdBy: draft.createdBy
        )

        try db.writer.write { dbConn in
            try Self.ensureJobStableId(dbConn: dbConn, jobId: jobId)
            try dbConn.execute(
                sql: "UPDATE jobs SET site_name = ?, updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL",
                arguments: [siteName, jobId]
            )
        }
        return try getJobRecord(id: jobId)
    }

    @discardableResult
    public func updateJobRecord(id: Int64, _ update: JobRecordUpdate) throws -> JobRecord {
        try updateJob(
            id: id,
            jobName: try update.jobName.map(Self.requiredTrimmed(_:)),
            customerName: Self.optionalTrimmed(update.customerName),
            addressLine1: nil,
            status: try update.status.map(Self.requiredTrimmed(_:)),
            priority: try update.priority.map(Self.requiredTrimmed(_:)),
            jobType: try update.jobType.map(Self.requiredTrimmed(_:)),
            notes: Self.optionalTrimmed(update.notes)
        )

        try db.writer.write { dbConn in
            try Self.ensureJobStableId(dbConn: dbConn, jobId: id)
            if update.siteName != nil {
                let siteName = Self.optionalTrimmed(update.siteName)
                try dbConn.execute(
                    sql: """
                        UPDATE jobs
                        SET site_name = ?, address_line1 = ?, updated_at = datetime('now')
                        WHERE id = ? AND deleted_at IS NULL
                        """,
                    arguments: [siteName, siteName, id]
                )
            }
        }
        return try getJobRecord(id: id)
    }

    public func getJobRecord(id: Int64) throws -> JobRecord {
        let record = try db.writer.read { dbConn -> JobRecord? in
            guard let row = try Row.fetchOne(dbConn, sql: Self.jobRecordSelectSQL + " WHERE id = ? AND deleted_at IS NULL", arguments: [id]) else {
                return nil
            }
            return try Self.jobRecord(from: row)
        }
        guard let record else { throw JobsError.jobNotFound(id) }
        return record
    }

    public func listJobRecords(search: String? = nil, status: String? = nil, limit: Int = 50, offset: Int = 0) throws -> [JobRecord] {
        try db.writer.read { dbConn in
            var clauses = ["deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []
            if let search = Self.optionalTrimmed(search) {
                clauses.append("(job_name LIKE ? OR job_number LIKE ? OR customer_name LIKE ? OR site_name LIKE ?)")
                let pattern = "%\(search)%"
                args += [pattern, pattern, pattern, pattern]
            }
            if let status = Self.optionalTrimmed(status) {
                clauses.append("status = ?")
                args.append(status)
            }
            args += [max(1, limit), max(0, offset)]
            let rows = try Row.fetchAll(
                dbConn,
                sql: Self.jobRecordSelectSQL + " WHERE \(clauses.joined(separator: " AND ")) ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?",
                arguments: StatementArguments(args)
            )
            return try rows.map(Self.jobRecord(from:))
        }
    }

    static func ensureJobStableId(dbConn: Database, jobId: Int64) throws {
        guard try dbConn.columns(in: "jobs").contains(where: { $0.name == "stable_id" }) else { return }
        let existing = try String.fetchOne(dbConn, sql: "SELECT stable_id FROM jobs WHERE id = ?", arguments: [jobId])
        guard Self.optionalTrimmed(existing) == nil else { return }
        try dbConn.execute(sql: "UPDATE jobs SET stable_id = ? WHERE id = ?", arguments: [UUID().uuidString, jobId])
    }

    private static let jobRecordSelectSQL = """
        SELECT id, stable_id, job_number, job_name, customer_name, site_name, address_line1,
               status, priority, job_type, notes, created_at, updated_at
        FROM jobs
        """

    private static func jobRecord(from row: Row) throws -> JobRecord {
        let id: Int64 = row["id"] ?? 0
        let stableId = try requiredTrimmed((row["stable_id"] as String?) ?? "")
        return JobRecord(
            id: id,
            stableId: stableId,
            jobNumber: row["job_number"] ?? "",
            jobName: row["job_name"] ?? "",
            customerName: row["customer_name"],
            siteName: (row["site_name"] as String?) ?? (row["address_line1"] as String?),
            status: row["status"] ?? "active",
            priority: row["priority"] ?? "normal",
            jobType: row["job_type"] ?? "service",
            notes: row["notes"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func requiredTrimmed(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JobsError.requiredFieldEmpty }
        return trimmed
    }

    private static func optionalTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
