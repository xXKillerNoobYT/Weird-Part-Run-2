import Foundation
import GRDB

// MARK: - Wire-Format Types

/// A change received from a peer device during sync.
/// This is the wire format — matches the JSON shape used by
/// the TypeScript peer-manager and Rust sync server.
public struct IncomingChange: Codable, Sendable {
    public var id: Int64?
    public var deviceId: String
    public var tableName: String
    public var recordId: String        // String to match _conflict_log schema
    public var operation: String       // "INSERT" | "UPDATE" | "DELETE"
    public var changedFields: String?  // JSON string of changed field key-value pairs
    public var oldValues: String?      // JSON string of previous field values
    public var recordData: String?     // JSON string of full row data (for INSERT/UPDATE)
    public var timestamp: String       // ISO 8601

    public init(
        id: Int64? = nil,
        deviceId: String,
        tableName: String,
        recordId: String,
        operation: String,
        changedFields: String? = nil,
        oldValues: String? = nil,
        recordData: String? = nil,
        timestamp: String
    ) {
        self.id = id
        self.deviceId = deviceId
        self.tableName = tableName
        self.recordId = recordId
        self.operation = operation
        self.changedFields = changedFields
        self.oldValues = oldValues
        self.recordData = recordData
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case tableName = "table_name"
        case recordId = "record_id"
        case operation
        case changedFields = "changed_fields"
        case oldValues = "old_values"
        case recordData = "record_data"
        case timestamp
    }
}

/// Result of applying a batch of incoming changes.
public struct MergeResult: Sendable {
    public var applied: Int = 0
    public var conflicts: Int = 0
    public var skipped: Int = 0
    public var errors: Int = 0

    public init(applied: Int = 0, conflicts: Int = 0, skipped: Int = 0, errors: Int = 0) {
        self.applied = applied
        self.conflicts = conflicts
        self.skipped = skipped
        self.errors = errors
    }
}

/// Conflict statistics for admin review.
public struct ConflictStats: Sendable {
    public let total: Int
    public let unreviewed: Int
    public let last24h: Int
}

// MARK: - Conflict Resolver

/// Field-level merge engine with Last-Write-Wins (LWW) per field.
///
/// Ported from: `src/local/conflict-resolver.ts`
///
/// Strategy:
/// 1. If Device A changes field X and Device B changes field Y — both apply (no conflict).
/// 2. If both changed the same field — the device with the later timestamp wins.
/// 3. Every overwrite is logged to `_conflict_log` regardless of which side wins.
public enum ConflictResolver {

    // MARK: - Table Name Whitelist

    /// Allowed table names for sync operations. Peer-supplied table names
    /// must appear in this set to prevent SQL injection via crafted sync data.
    static let allowedSyncTables: Set<String> = [
        // Foundation
        "users", "hats", "hat_permissions", "user_hats", "job_lead_elevations",
        "devices", "settings", "activity_log", "notifications", "notification_preferences",
        // Parts & Inventory
        "part_categories", "part_styles", "part_types", "part_colors",
        "brands", "suppliers", "parts", "brand_supplier_links", "part_supplier_links",
        "stock", "stock_movements", "pulled_staging_tags", "bill_rate_types",
        "type_color_links", "type_brand_links",
        // Jobs & Labor
        "jobs", "job_parts", "labor_entries", "clock_out_questions", "clock_out_responses",
        "one_time_questions", "daily_reports", "job_team_members", "job_preferred_suppliers",
        "job_customers", "job_general_contractors",
        // Notebooks
        "notebook_templates", "template_sections", "template_entries",
        "notebooks", "notebook_section_groups", "notebook_sections", "notebook_entries", "notebook_templates",
        "notebook_entry_permissions", "task_order_links", "notebook_entry_tools",
        // Orders & Procurement
        "job_parts_orders", "jpo_line_items", "purchase_orders", "po_line_items",
        "returns", "return_line_items", "order_status_history",
        "special_items", "job_preferences", "order_attachments",
        "po_jpo_links", "po_conversations", "po_groups", "po_group_members",
        "category_supplier_preferences", "job_supplier_preferences",
        // Fleet & Vehicles
        "vehicles", "vehicle_assignments", "vehicle_delivery_items",
        "job_trailers", "trailer_location_events",
        "maintenance_types", "maintenance_schedules", "maintenance_records",
        "mileage_logs", "trip_legs", "mileage_reimbursements", "fuel_logs",
        "trailer_stock_templates", "trailer_stock_template_lines",
        // Tools
        "tools", "kit_templates", "tool_movements",
        "kit_verification_sessions", "kit_verification_items",
        "tool_maintenance_types", "tool_maintenance_schedules", "tool_maintenance_records",
        "tool_depreciation_entries",
        // People
        "customers", "general_contractors", "certifications", "wage_history",
        "employee_notes", "user_skills", "employee_teams", "employee_team_members",
        "entity_contacts",
        // Scheduling
        "employee_default_schedules", "schedule_exceptions", "job_dispatch",
        "subcontractor_schedules", "dispatch_templates", "dispatch_template_members",
        "shift_patterns", "shift_pattern_days",
        // Chat
        "chat_channels", "chat_channel_members", "qa_threads",
        "chat_messages", "chat_read_receipts", "chat_mentions",
        "rfi_objects", "qa_escalations", "message_attachments",
        // Reports & Billing
        "billing_periods", "report_annotations", "report_share_tokens", "report_templates",
        "saved_reports",
        "pto_policies", "pto_transactions", "pto_balances",
        // Warehouse
        "receiving_sessions", "receiving_session_items",
        "warehouse_locations", "stock_entries",
        "staging_zones", "staging_items", "staging_boxes",
        "warehouse_floor_plans", "warehouse_floor_features",
        "warehouse_storage_units", "warehouse_storage_levels",
        "warehouse_storage_areas", "warehouse_bins", "warehouse_part_assignments",
        "warehouse_user_positions", "warehouse_onboarding_progress",
        // Audit confidence
        "part_confidence", "audit_sessions_v2", "audit_counts",
        "misplaced_parts_log", "user_warehouse_ratings", "organization_ratings",
        "consolidation_votes", "consolidation_vote_entries",
        // Break compliance
        "break_policies", "break_bonuses", "break_records", "company_break_settings",
        // Payment tracking & communication
        "payment_records", "customer_communications", "contractor_notes", "contractor_ratings",
        // Work classification audit
        "classification_history",
        // Estimation
        "estimation_questions", "estimation_responses", "estimation_results",
        "estimation_reviews", "estimation_question_rejections",
        // Tool Detail
        "tool_checkouts", "tool_change_log", "tool_trades", "tool_maintenance_configs",
        // Vehicle Stock & Trailers
        "vehicle_stock", "trailer_attachments",
        "trailer_storage_units", "trailer_stock", "trailer_location_history",
        // Pre-Trip Inspections
        "inspection_templates", "inspection_records", "inspection_results",
        // Suppliers
        "supplier_portal_tokens", "supplier_po_acknowledgments", "supplier_contact_ratings",
        // Costs
        "cost_layers", "company_cost_settings", "company_profiles",
        "pricing_tiers", "price_history", "cost_layer_consumptions",
        "scheduled_deletions",
        // Business
        "business_profiles",
        // Companions
        "companion_rules", "companion_rule_sources", "companion_rule_targets",
        "companion_suggestions", "companion_suggestion_sources",
        "co_occurrence_pairs", "companion_feedback", "part_alternatives",
        "companion_polls", "companion_votes", "companion_poll_results",
        "companion_auto_discovery_log",
        // Supplier communication bridge
        "supplier_channel_bridges", "supplier_messages",
        // Per-location forecasting
        "location_stock_targets", "forecast_settings", "location_free_space",
        "target_recommendations",
        // AI (not _text_history — that's local-only)
        "part_image_features", "image_match_history",
        // Sync infrastructure (these are managed by sync itself)
        "_change_log", "_conflict_log", "_vector_clock", "_device_registry",
        "_binary_attachments", "_sync_transfer_log",
    ]

    /// Validate that a table name is in the whitelist.
    /// Returns false for unknown or potentially malicious table names.
    public static func isAllowedTable(_ name: String) -> Bool {
        allowedSyncTables.contains(name.lowercased())
    }

    // MARK: - Public API

    /// Apply incoming peer changes with field-level LWW merge.
    ///
    /// Never throws for individual change failures — increments `result.errors` instead.
    /// This ensures one bad change doesn't block the rest of the batch.
    public static func resolveAndApplyChanges(
        db: AppDatabase,
        changes: [IncomingChange],
        localDeviceId: String? = nil
    ) throws -> MergeResult {
        var result = MergeResult()
        let localDevice = localDeviceId ?? DeviceIdentity.current

        for change in changes {
            // Reject changes with invalid/unknown table names to prevent SQL injection
            guard isAllowedTable(change.tableName) else {
                result.skipped += 1
                continue
            }

            do {
                try db.writer.write { dbConn in
                    switch change.operation.uppercased() {
                    case "DELETE":
                        try applyDelete(db: dbConn, change: change)
                        result.applied += 1

                    case "INSERT":
                        let conflictCount = try applyInsert(db: dbConn, change: change, localDeviceId: localDevice)
                        result.applied += 1
                        result.conflicts += conflictCount

                    case "UPDATE":
                        let conflictCount = try applyUpdate(db: dbConn, change: change, localDeviceId: localDevice)
                        result.applied += 1
                        result.conflicts += conflictCount

                    default:
                        result.skipped += 1
                    }
                }
            } catch {
                result.errors += 1
            }
        }

        return result
    }

    /// Get unreviewed conflicts for admin review.
    public static func getUnreviewedConflicts(
        db: AppDatabase,
        limit: Int = 50
    ) throws -> [ConflictLogEntry] {
        try db.writer.read { dbConn in
            try ConflictLogEntry.fetchAll(
                dbConn,
                sql: "SELECT * FROM _conflict_log WHERE reviewed = 0 ORDER BY resolved_at DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }

    /// Mark a conflict as reviewed by an admin.
    public static func markConflictReviewed(
        db: AppDatabase,
        conflictId: Int64
    ) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ?",
                arguments: [conflictId]
            )
        }
    }

    /// Get conflict statistics.
    public static func getConflictStats(
        db: AppDatabase
    ) throws -> ConflictStats {
        try db.writer.read { dbConn in
            let total = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _conflict_log") ?? 0
            let unreviewed = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _conflict_log WHERE reviewed = 0") ?? 0
            let last24h = try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _conflict_log WHERE resolved_at > datetime('now', '-1 day')"
            ) ?? 0
            return ConflictStats(total: total, unreviewed: unreviewed, last24h: last24h)
        }
    }

    // MARK: - Private: Apply Operations

    /// Apply a DELETE change — soft delete (set deleted_at), fallback to hard delete.
    private static func applyDelete(db: Database, change: IncomingChange) throws {
        let table = change.tableName
        let recordId = change.recordId

        // Try soft delete first
        do {
            try db.execute(
                sql: "UPDATE \(quotedTable(table)) SET deleted_at = ? WHERE id = ?",
                arguments: [change.timestamp, recordId]
            )
            if db.changesCount == 0 {
                // Record doesn't exist — nothing to delete, which is fine
            }
        } catch {
            // No deleted_at column — fall back to hard delete
            try db.execute(
                sql: "DELETE FROM \(quotedTable(table)) WHERE id = ?",
                arguments: [recordId]
            )
        }
    }

    /// Apply an INSERT change — if record exists, field-level LWW merge.
    /// Returns conflict count.
    @discardableResult
    private static func applyInsert(
        db: Database,
        change: IncomingChange,
        localDeviceId: String
    ) throws -> Int {
        let table = change.tableName
        let recordId = change.recordId

        // Parse incoming data
        guard let recordDataFields = parseJsonField(change.recordData) else {
            // No data to insert
            return 0
        }

        // Check if record exists locally
        let localRow = try getLocalRecord(db: db, tableName: table, recordId: recordId)

        guard let existingRow = localRow else {
            // Record doesn't exist locally — plain INSERT
            let columns = recordDataFields.keys.sorted()
            let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
            let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
            let values = columns.map { recordDataFields[$0] ?? "" }

            try db.execute(
                sql: "INSERT OR IGNORE INTO \(quotedTable(table)) (\(columnList)) VALUES (\(placeholders))",
                arguments: StatementArguments(values)
            )
            return 0
        }

        // Record exists — field-level LWW merge
        return try fieldLevelMerge(
            db: db,
            table: table,
            recordId: recordId,
            localRow: existingRow,
            incomingFields: recordDataFields,
            change: change,
            localDeviceId: localDeviceId
        )
    }

    /// Apply an UPDATE change with changed_fields — field-level LWW merge.
    /// Returns conflict count.
    @discardableResult
    private static func applyUpdate(
        db: Database,
        change: IncomingChange,
        localDeviceId: String
    ) throws -> Int {
        let table = change.tableName
        let recordId = change.recordId

        // Parse changed_fields
        let changedFields = parseJsonField(change.changedFields)

        if changedFields == nil && change.recordData != nil {
            // No changed_fields but has record_data — delegate to INSERT logic (full-record merge)
            return try applyInsert(db: db, change: change, localDeviceId: localDeviceId)
        }

        guard let incomingFields = changedFields else {
            return 0
        }

        // Check if record exists locally
        let localRow = try getLocalRecord(db: db, tableName: table, recordId: recordId)

        guard let existingRow = localRow else {
            // Record doesn't exist locally
            if let recordDataFields = parseJsonField(change.recordData) {
                // We have full record data — INSERT it
                let columns = recordDataFields.keys.sorted()
                let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
                let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
                let values = columns.map { recordDataFields[$0] ?? "" }

                try db.execute(
                    sql: "INSERT OR IGNORE INTO \(quotedTable(table)) (\(columnList)) VALUES (\(placeholders))",
                    arguments: StatementArguments(values)
                )
            }
            return 0
        }

        // Record exists — field-level LWW merge
        return try fieldLevelMerge(
            db: db,
            table: table,
            recordId: recordId,
            localRow: existingRow,
            incomingFields: incomingFields,
            change: change,
            localDeviceId: localDeviceId
        )
    }

    // MARK: - Private: Field-Level LWW Merge

    /// The core merge algorithm.
    /// For each incoming field, check if it conflicts with a local unsynced change.
    /// If no conflict: accept remote. If conflict: later timestamp wins.
    /// Returns conflict count.
    private static func fieldLevelMerge(
        db: Database,
        table: String,
        recordId: String,
        localRow: Row,
        incomingFields: [String: String],
        change: IncomingChange,
        localDeviceId: String
    ) throws -> Int {
        // Get fields that have been locally modified but not yet synced
        let localChangedFields = try getLocalChangedFields(db: db, tableName: table, recordId: recordId)

        // Get local timestamp for conflict comparison
        let localTimestamp: String
        if let updatedAt: String = localRow["updated_at"] {
            localTimestamp = updatedAt
        } else if let createdAt: String = localRow["created_at"] {
            localTimestamp = createdAt
        } else {
            localTimestamp = "1970-01-01T00:00:00Z"
        }

        let remoteTimestamp = change.timestamp

        var mergedData: [String: String] = [:]
        var conflictEntries: [ConflictLogEntry] = []

        for (field, remoteValue) in incomingFields {
            // Always skip "id" — primary key is never merged
            if field == "id" { continue }

            if localChangedFields.contains(field) {
                // Both local and remote modified this field — LWW
                let localValue = stringifyValue(localRow[field] as DatabaseValue)
                let winner: String
                if remoteTimestamp > localTimestamp {
                    // Remote wins
                    winner = "remote"
                    mergedData[field] = remoteValue
                } else {
                    // Local wins (or tie goes to local)
                    winner = "local"
                }

                conflictEntries.append(ConflictLogEntry(
                    tableName: table,
                    recordId: recordId,
                    fieldName: field,
                    localValue: localValue,
                    remoteValue: remoteValue,
                    winner: winner,
                    localDevice: localDeviceId,
                    remoteDevice: change.deviceId,
                    localTs: localTimestamp,
                    remoteTs: remoteTimestamp,
                    resolvedAt: currentTimestamp()
                ))
            } else {
                // Field not locally modified — accept remote value
                mergedData[field] = remoteValue
            }
        }

        // Apply merged fields
        if !mergedData.isEmpty {
            let setClauses = mergedData.keys.sorted().map { "\"\($0)\" = ?" }.joined(separator: ", ")
            let values = mergedData.keys.sorted().compactMap { mergedData[$0] }
            var args: [any DatabaseValueConvertible] = values
            args.append(recordId)

            try db.execute(
                sql: "UPDATE \(quotedTable(table)) SET \(setClauses) WHERE id = ?",
                arguments: StatementArguments(args)
            )
        }

        // Log all conflicts
        if !conflictEntries.isEmpty {
            try logConflicts(db: db, conflicts: conflictEntries)
        }

        return conflictEntries.count
    }

    // MARK: - Private: Helpers

    /// Fetch a local record by ID from any table.
    private static func getLocalRecord(db: Database, tableName: String, recordId: String) throws -> Row? {
        try Row.fetchOne(
            db,
            sql: "SELECT * FROM \(quotedTable(tableName)) WHERE id = ?",
            arguments: [recordId]
        )
    }

    /// Get the set of field names that have been locally modified but not yet synced.
    /// Queries `_change_log WHERE table_name=? AND record_id=? AND synced=0`.
    /// Note: `_change_log.record_id` is INTEGER, so we cast the String to Int64.
    private static func getLocalChangedFields(
        db: Database,
        tableName: String,
        recordId: String
    ) throws -> Set<String> {
        let recordIdInt = Int64(recordId) ?? 0
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT changed_fields FROM _change_log
                WHERE table_name = ? AND record_id = ? AND synced = 0
                ORDER BY timestamp DESC
                """,
            arguments: [tableName, recordIdInt]
        )

        var result = Set<String>()
        for row in rows {
            if let jsonString: String = row["changed_fields"],
               let fields = parseJsonField(jsonString) {
                result.formUnion(fields.keys)
            }
        }
        return result
    }

    /// Insert conflict entries into `_conflict_log`.
    private static func logConflicts(db: Database, conflicts: [ConflictLogEntry]) throws {
        for var conflict in conflicts {
            try conflict.insert(db)
        }
    }

    /// Parse a JSON string into a dictionary.
    /// Handles: nil → nil, already a dict string → parsed, garbage → nil.
    static func parseJsonField(_ field: String?) -> [String: String]? {
        guard let str = field, !str.isEmpty else { return nil }
        guard let data = str.data(using: .utf8) else { return nil }

        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            if let dict = obj as? [String: Any] {
                var result: [String: String] = [:]
                for (key, value) in dict {
                    if value is NSNull {
                        // Represent NULL as empty string — the column may need NULL
                        result[key] = ""
                    } else if let s = value as? String {
                        result[key] = s
                    } else {
                        result[key] = "\(value)"
                    }
                }
                return result
            }
        } catch {
            // Not valid JSON — return nil
        }
        return nil
    }

    /// Convert a DatabaseValue to a string for conflict logging.
    private static func stringifyValue(_ value: DatabaseValue) -> String? {
        switch value.storage {
        case .null:
            return nil
        case .int64(let v):
            return "\(v)"
        case .double(let v):
            return "\(v)"
        case .string(let v):
            return v
        case .blob(let v):
            return v.base64EncodedString()
        }
    }

    /// Current UTC timestamp in ISO 8601 format (consistent with SyncEngine).
    private static func currentTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    /// Quote a table name to prevent SQL injection.
    private static func quotedTable(_ name: String) -> String {
        // Double-quote the table name — standard SQL quoting
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
