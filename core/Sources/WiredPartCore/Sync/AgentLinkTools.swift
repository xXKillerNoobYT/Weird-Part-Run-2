import Foundation
import GRDB

/// The v1 Agent Link tool registry — the plan's seven read tools plus the one
/// scoped write (`job_note_append`), each a thin JSON adapter over an existing
/// core service so soft-delete filtering, permission gates, and business rules
/// stay in exactly one place. Output is compact JSON: agents pay per token.
public enum AgentLinkTools {

    struct ToolError: Error, CustomStringConvertible {
        let description: String
        init(_ message: String) { description = message }
    }

    // MARK: - Argument helpers

    private static func args(_ data: Data?) -> [String: Any] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func intArg(_ dict: [String: Any], _ key: String) -> Int64? {
        if let n = dict[key] as? NSNumber { return n.int64Value }
        if let s = dict[key] as? String { return Int64(s) }
        return nil
    }

    private static func encode(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Clamp agent-supplied limits: positive, and never larger than `cap`.
    private static func limit(_ dict: [String: Any], cap: Int, default def: Int) -> Int {
        guard let raw = (dict["limit"] as? NSNumber)?.intValue else { return def }
        return min(max(raw, 1), cap)
    }

    // MARK: - Registry

    public static func v1(
        db: AppDatabase,
        parts: PartsService,
        jobs: JobsService,
        orders: OrdersService,
        notebooks: NotebooksService,
        reports: ReportsService,
        deviceLogs: DeviceLogService? = nil,
        appVersion: String = "dev"
    ) -> AgentLinkToolRegistry {
        let logs = deviceLogs ?? DeviceLogService(db: db, appVersion: appVersion)
        return AgentLinkToolRegistry(tools: [

            AgentLinkTool(
                name: "parts_search",
                description: "Search parts by name, code, or color abbreviation. Returns id, name, code, type, and unit.",
                inputSchemaJSON: #"{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"integer","maximum":50}},"required":["query"]}"#
            ) { _, data in
                let a = args(data)
                guard let query = a["query"] as? String, !query.isEmpty else {
                    throw ToolError("missing required argument: query")
                }
                let found = try parts.searchParts(query: query, limit: limit(a, cap: 50, default: 20))
                return try encode(found.map { p -> [String: Any] in
                    var row: [String: Any] = ["id": p.id ?? 0, "name": p.name, "partType": p.partType]
                    if let code = p.code { row["code"] = code }
                    if let d = p.description { row["description"] = d }
                    if let u = p.unitOfMeasure { row["unit"] = u }
                    return row
                })
            },

            AgentLinkTool(
                name: "stock_levels",
                description: "Current stock for one part: total on hand and a breakdown by location type.",
                inputSchemaJSON: #"{"type":"object","properties":{"part_id":{"type":"integer"}},"required":["part_id"]}"#
            ) { _, data in
                let a = args(data)
                guard let partId = intArg(a, "part_id") else {
                    throw ToolError("missing required argument: part_id")
                }
                let summary = try parts.getPartStockSummary(partId: partId)
                return try encode([
                    "partId": partId,
                    "total": summary.total,
                    "byLocationType": summary.byLocationType,
                ])
            },

            AgentLinkTool(
                name: "jobs_list",
                description: "List jobs with status, priority, schedule, labor hours, and cost. Optional search and status filters.",
                inputSchemaJSON: #"{"type":"object","properties":{"search":{"type":"string"},"status":{"type":"string"},"limit":{"type":"integer","maximum":50}}}"#
            ) { _, data in
                let a = args(data)
                let rows = try jobs.listJobs(
                    search: a["search"] as? String,
                    status: a["status"] as? String,
                    limit: limit(a, cap: 50, default: 25)
                )
                return try encode(rows.map { j -> [String: Any] in
                    var row: [String: Any] = [
                        "id": j.id, "jobNumber": j.jobNumber, "jobName": j.jobName,
                        "status": j.status, "priority": j.priority,
                        "laborHours": j.laborHours, "actualCost": j.actualCost,
                    ]
                    if let c = j.customerName { row["customer"] = c }
                    if let d = j.dueDate { row["dueDate"] = d }
                    return row
                })
            },

            AgentLinkTool(
                name: "job_detail",
                description: "One job in detail: identity, customer, address, status, type, and estimates.",
                inputSchemaJSON: #"{"type":"object","properties":{"job_id":{"type":"integer"}},"required":["job_id"]}"#
            ) { _, data in
                let a = args(data)
                guard let jobId = intArg(a, "job_id") else {
                    throw ToolError("missing required argument: job_id")
                }
                let j = try jobs.getJob(id: jobId)
                var row: [String: Any] = [
                    "id": j.id, "jobNumber": j.jobNumber, "jobName": j.jobName,
                    "status": j.status, "priority": j.priority, "jobType": j.jobType,
                ]
                if let c = j.customerName { row["customer"] = c }
                let address = [j.addressLine1, j.city, j.state, j.zip]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                if !address.isEmpty { row["address"] = address }
                if let e = j.estimatedHours { row["estimatedHours"] = e }
                if let lead = j.leadUserName { row["lead"] = lead }
                return try encode(row)
            },

            AgentLinkTool(
                name: "orders_status",
                description: "Open job purchase orders (JPOs) with status, priority, line counts, and due dates. Optional status filter.",
                inputSchemaJSON: #"{"type":"object","properties":{"status":{"type":"string"},"limit":{"type":"integer","maximum":50}}}"#
            ) { _, data in
                let a = args(data)
                let rows = try orders.listJPOs(
                    status: a["status"] as? String,
                    limit: limit(a, cap: 50, default: 25)
                )
                return try encode(rows.map { o -> [String: Any] in
                    var row: [String: Any] = [
                        "id": o.id, "jobId": o.jobId, "jobName": o.jobName,
                        "status": o.status, "priority": o.priority,
                        "lines": o.lineCount, "holds": o.holdCount,
                    ]
                    if let d = o.dueDate { row["dueDate"] = d }
                    if let c = o.createdAt { row["createdAt"] = c }
                    return row
                })
            },

            AgentLinkTool(
                name: "reports_summary",
                description: "Headline numbers: spending over the last N days (default 30) and job counts.",
                inputSchemaJSON: #"{"type":"object","properties":{"days":{"type":"integer","minimum":1,"maximum":365}}}"#
            ) { _, data in
                let a = args(data)
                let days = min(max((a["days"] as? NSNumber)?.intValue ?? 30, 1), 365)
                let spend = try reports.getSpendingSummary(days: days)
                let stats = try jobs.getJobStats()
                var row: [String: Any] = [
                    "days": days,
                    "totalSpend": spend.totalSpend,
                    "poCount": spend.poCount,
                    "avgPOAmount": spend.avgPOAmount,
                    "jobsActive": stats.active,
                    "jobsCompleted": stats.completed,
                    "jobsTotal": stats.total,
                ]
                if let top = spend.topSupplierName {
                    row["topSupplier"] = top
                    row["topSupplierAmount"] = spend.topSupplierAmount
                }
                return try encode(row)
            },

            // Fleet diagnostics (owner 2026-08-03): field devices replicate
            // their technical logs to this Mac, and an agent reads them here
            // instead of asking the owner for screenshots.
            AgentLinkTool(
                name: "device_logs_recent",
                description: "Recent technical log entries from THIS device and every field device that has synced (sync failures, pairing errors, startup problems). Filter by level (error/warn/info), category, or device_id.",
                inputSchemaJSON: #"{"type":"object","properties":{"limit":{"type":"integer","maximum":500},"level":{"type":"string","enum":["error","warn","info"]},"category":{"type":"string"},"device_id":{"type":"string"}}}"#
            ) { _, data in
                let a = args(data)
                let level = (a["level"] as? String).flatMap(DeviceLogService.Level.init(rawValue:))
                let entries = try logs.recent(
                    limit: limit(a, cap: 500, default: 100),
                    level: level,
                    category: a["category"] as? String,
                    deviceId: a["device_id"] as? String
                )
                return try encode(entries.map { e -> [String: Any] in
                    var row: [String: Any] = [
                        "at": e.createdAt, "device": e.deviceName ?? e.deviceId,
                        "level": e.level.rawValue, "category": e.category,
                        "message": e.message,
                    ]
                    if let d = e.detail { row["detail"] = d }
                    if let v = e.appVersion { row["appVersion"] = v }
                    return row
                })
            },

            AgentLinkTool(
                name: "device_logs_summary",
                description: "Which devices have reported logs, with error counts and last-seen times — the fleet health view.",
                inputSchemaJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#
            ) { _, _ in
                try encode(try logs.deviceSummary().map { d -> [String: Any] in
                    var row: [String: Any] = [
                        "deviceId": d.deviceId, "errors": d.errors, "total": d.total,
                    ]
                    if let n = d.deviceName { row["device"] = n }
                    if let s = d.lastSeen { row["lastSeen"] = s }
                    return row
                })
            },

            AgentLinkTool(
                name: "system_health",
                description: "App version, database schema version, and Agent Link status for this WiredPart device.",
                inputSchemaJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#
            ) { _, _ in
                let (migrationCount, latest) = try db.writer.read { dbc -> (Int, String) in
                    let count = try Int.fetchOne(
                        dbc, sql: "SELECT COUNT(*) FROM grdb_migrations"
                    ) ?? 0
                    let last = try String.fetchOne(
                        dbc, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1"
                    ) ?? "none"
                    return (count, last)
                }
                return try encode([
                    "appVersion": appVersion,
                    "migrationsApplied": migrationCount,
                    "latestMigration": latest,
                    "agentLink": "ok",
                ])
            },

            // The single v1 write. Append-only: it can create a note, never
            // edit or delete one. Acts as the user who created the link and
            // passes through the normal manage_notebooks permission gate.
            AgentLinkTool(
                name: "job_note_append",
                description: "Append a note to a job's notebook (creates the notebook if the job has none). The note is attributed to the user who created this agent link.",
                inputSchemaJSON: #"{"type":"object","properties":{"job_id":{"type":"integer"},"note":{"type":"string"},"title":{"type":"string"}},"required":["job_id","note"]}"#
            ) { link, data in
                let a = args(data)
                guard let jobId = intArg(a, "job_id") else {
                    throw ToolError("missing required argument: job_id")
                }
                guard let note = a["note"] as? String, !note.isEmpty else {
                    throw ToolError("missing required argument: note")
                }
                guard let actingUser = link.createdBy else {
                    throw ToolError(
                        "this link has no acting user — recreate it from the Devices page so notes can be attributed"
                    )
                }
                // Verify the job exists before touching notebooks (clear error
                // beats a foreign-key surprise).
                _ = try jobs.getJob(id: jobId)
                let notebookId: Int64
                if let existing = try notebooks.listNotebooks(notebookType: "job", jobId: jobId).first {
                    notebookId = existing.id
                } else {
                    notebookId = try notebooks.createNotebook(
                        title: "Job Notebook",
                        notebookType: "job",
                        jobId: jobId,
                        createdBy: actingUser
                    )
                }
                let entryId = try notebooks.addNotebookEntry(
                    notebookId: notebookId,
                    title: (a["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Agent note",
                    content: note,
                    entryType: "note",
                    createdBy: actingUser
                )
                return try encode(["notebookId": notebookId, "entryId": entryId, "status": "appended"])
            },
        ])
    }
}
