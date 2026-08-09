import Foundation
import GRDB
import os.log

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

    /// Accumulate one change's outcome. Keeps the batched and streamed atomic
    /// apply paths tallying identically instead of by copy-paste.
    mutating func add(_ outcome: (applied: Int, conflicts: Int, skipped: Int)) {
        applied += outcome.applied
        conflicts += outcome.conflicts
        skipped += outcome.skipped
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

    private static let logger = Logger(subsystem: "com.wiredpart.core", category: "ConflictResolver")

    // MARK: - Errors

    /// Errors thrown by apply functions to distinguish skipped-but-expected
    /// situations from real database failures.
    public enum ApplyError: Error, Sendable {
        /// An UPDATE arrived for a record that doesn't exist locally and the
        /// change had no full-record payload. Caller should count as skipped
        /// and request a full resync for this record. (Fixes #220)
        case missingLocalRecord(table: String, recordId: String)
    }


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
        // 100%-sync gap closure (owner directive 2026-08-01, audit on #1417):
        // business tables that predated any classification gate. Their change
        // triggers are installed by migration 119 (frozen copy of this list).
        "wishlist_items", "color_brand_skus", "color_supplier_costs", "part_change_log",
        "job_stages", "job_stage_templates", "job_stage_category_map",
        "job_return_intakes", "job_return_intake_items",
        "shift_templates", "company_holidays", "overtime_settings",
        "vehicle_issue_reports", "vehicle_location_logs",
        "warehouse_zones", "warehouse_walking_paths", "warehouse_walking_path_stops",
        "staging_box_contents",
        "audit_session_events", "multi_user_audit_assignments",
        "timesheet_correction_audits", "labor_entry_correction_audits",
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
        // AI (not _text_history — that's local-only). part_image_features is
        // intentionally ABSENT: its feature_vector is a NOT NULL BLOB, and row
        // JSON cannot carry blobs (see PeerManager.jsonRecordDict) — every row
        // silently failed to apply on the receiver. Feature vectors are
        // device-derived from local photos; binary payloads belong to
        // BinarySyncManager (Copilot review on PR #1422).
        "image_match_history",
        // Fleet diagnostics — every device's technical log replicates so
        // field failures are readable from the shop Mac (owner 2026-08-03).
        // Its change triggers are installed by migration 121, NOT by 119:
        // 119 uses a frozen table list that predates this table.
        "device_logs",
        // Sync infrastructure (these are managed by sync itself)
        "_change_log", "_conflict_log", "_vector_clock", "_device_registry",
        "_binary_attachments", "_sync_transfer_log",
    ]

    /// Validate that a table name is in the whitelist.
    /// Returns false for unknown or potentially malicious table names.
    /// Tables that intentionally NEVER sync — device-scoped by design.
    /// Every table in the database must appear in exactly one of
    /// `allowedSyncTables` or this set; `SyncTableClassificationTests`
    /// fails the build when a new table is left unclassified (the gap that
    /// silently accumulated 22 unsynced business tables until 2026-08-01).
    static let deviceLocalTables: Set<String> = [
        // Per-Mac AI agent keys and their audit trail — trust is per device.
        "agent_links", "agent_link_calls",
        // Per-device login sessions.
        "auth_token_sessions",
        // Local wizard/import scratch state.
        "company_setup_draft", "part_import_sessions",
        "part_import_row_evidence", "part_import_saved_mappings",
        // Local operational logs and locks (lock semantics cannot survive
        // asynchronous merge).
        "background_task_log", "notebook_entry_edit_locks",
        // On-device AI conversations (architecture: never leave the device).
        "ai_conversation_messages",
        // Regenerable ML derivatives.
        "part_image_features",
        // On-device estimation calibration.
        "estimation_question_accuracy_reviews",
    ]

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
                let outcome = try db.writer.write { dbConn -> (applied: Int, conflicts: Int, skipped: Int) in
                    // Echo guard: while this transaction applies a PEER's change,
                    // the change-tracking triggers (migration 112) must not log
                    // the write — otherwise every applied change would be re-
                    // pushed back to the peer forever. The guard row lives only
                    // inside this transaction (rolled back with it on failure).
                    try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")

                    let outcome: (applied: Int, conflicts: Int, skipped: Int)

                    // `_device_registry` is keyed by device_id (TEXT), not `id`,
                    // so the generic id-keyed apply below could NEVER apply it —
                    // every incoming row failed with "no such column: id" and was
                    // swallowed as result.errors. Net effect (security audit
                    // 2026-08-03, P0): deactivating a lost/stolen device revoked
                    // it ONLY on the device that performed the revocation; every
                    // other paired device kept treating it as trusted forever.
                    if change.tableName == "_device_registry" {
                        let applied = try applyDeviceRegistryChange(db: dbConn, change: change)
                        try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
                        return (applied, 0, applied == 1 ? 0 : 1)
                    }

                    switch change.operation.uppercased() {
                    case "DELETE":
                        try applyDelete(db: dbConn, change: change, localDeviceId: localDevice)
                        outcome = (1, 0, 0)

                    case "INSERT":
                        let conflictCount = try applyInsert(db: dbConn, change: change, localDeviceId: localDevice)
                        outcome = (1, conflictCount, 0)

                    case "UPDATE":
                        let conflictCount = try applyUpdate(db: dbConn, change: change, localDeviceId: localDevice)
                        outcome = (1, conflictCount, 0)

                    default:
                        outcome = (0, 0, 1)
                    }

                    // Cleanup participates in the transaction: failure rolls back
                    // the peer write instead of silently disabling local tracking.
                    try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
                    return outcome
                }
                result.applied += outcome.applied
                result.conflicts += outcome.conflicts
                result.skipped += outcome.skipped
            } catch ApplyError.missingLocalRecord {
                // Fix #220: UPDATE for a record we don't have yet — count as skipped,
                // not errored. A follow-up full-record resync should re-deliver it.
                result.skipped += 1
            } catch {
                result.errors += 1
                logger.error("Failed to apply incoming change: \(error.localizedDescription, privacy: .public)")
            }
        }

        return result
    }

    /// Apply a batch in one database transaction or roll the entire batch back.
    ///
    /// Initial Bluetooth snapshots use this stricter contract: reporting an apply
    /// failure while retaining a successful prefix would leave onboarding with a
    /// partial company snapshot. Normal ongoing sync keeps the best-effort API above.
    static func resolveAndApplyChangesAtomically(
        db: AppDatabase,
        changes: [IncomingChange],
        localDeviceId: String? = nil
    ) throws -> MergeResult {
        let localDevice = localDeviceId ?? DeviceIdentity.current

        return try db.writer.write { dbConn in
            var result = MergeResult()
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            defer { try? dbConn.execute(sql: "DELETE FROM _sync_apply_guard") }

            for change in changes {
                result.add(try applyOneAtomically(dbConn, change, localDevice))
            }

            return result
        }
    }

    /// Streaming twin of `resolveAndApplyChangesAtomically` for a change source
    /// too large to hold in memory (WEI-7022).
    ///
    /// The joiner's initial Bluetooth snapshot is a whole company. Decoding it
    /// into one `[IncomingChange]` before applying is exactly the unbounded
    /// allocation this exists to avoid, so the caller instead *produces*
    /// changes one at a time — typically by walking a cursor over its durable
    /// staging table on the very connection this transaction owns.
    ///
    /// The contract is otherwise identical and deliberately so: one
    /// transaction, one echo guard, and any throw rolls the ENTIRE snapshot
    /// back. A partially applied company is worse than no company, because
    /// nothing downstream can tell the difference between the two.
    static func resolveAndApplyStreamedChangesAtomically(
        db: AppDatabase,
        localDeviceId: String? = nil,
        produceChanges: (Database, (IncomingChange) throws -> Void) throws -> Void
    ) throws -> MergeResult {
        let localDevice = localDeviceId ?? DeviceIdentity.current

        return try db.writer.write { dbConn in
            var result = MergeResult()
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            defer { try? dbConn.execute(sql: "DELETE FROM _sync_apply_guard") }

            try produceChanges(dbConn) { change in
                result.add(try applyOneAtomically(dbConn, change, localDevice))
            }

            return result
        }
    }

    /// Apply one change inside a caller-owned atomic transaction.
    ///
    /// Anything other than `missingLocalRecord` propagates so the caller's
    /// transaction rolls back — that is the all-or-nothing guarantee.
    private static func applyOneAtomically(
        _ dbConn: Database,
        _ change: IncomingChange,
        _ localDeviceId: String
    ) throws -> (applied: Int, conflicts: Int, skipped: Int) {
        guard isAllowedTable(change.tableName) else { return (0, 0, 1) }

        do {
            switch change.operation.uppercased() {
            case "DELETE":
                try applyDelete(db: dbConn, change: change, localDeviceId: localDeviceId)
                return (1, 0, 0)
            case "INSERT":
                let conflictCount = try applyInsert(
                    db: dbConn,
                    change: change,
                    localDeviceId: localDeviceId
                )
                return (1, conflictCount, 0)
            case "UPDATE":
                let conflictCount = try applyUpdate(
                    db: dbConn,
                    change: change,
                    localDeviceId: localDeviceId
                )
                return (1, conflictCount, 0)
            default:
                return (0, 0, 1)
            }
        } catch ApplyError.missingLocalRecord {
            // Fix #220: an UPDATE for a record we do not have yet is a skip,
            // not an error — a later full-record resync re-delivers it.
            return (0, 0, 1)
        }
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
                sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ? AND reviewed = 0",
                arguments: [conflictId]
            )
            guard dbConn.changesCount == 1 else {
                throw ConflictReviewError.conflictNotPending(conflictId)
            }
        }
    }

    // MARK: - Manual Conflict Resolution

    /// Which side the reviewer chose to keep.
    public enum ConflictResolutionChoice: Sendable {
        case keepLocal
        case keepRemote
    }

    public enum ConflictReviewError: Error, LocalizedError, Sendable {
        case missingConflictId
        case conflictNotPending(Int64)
        case tableNotAllowed(String)
        case invalidRecordId(String)
        case unknownField(table: String, field: String)
        case fieldNotTextResolvable(table: String, field: String)
        case missingLiveRecord(table: String, recordId: String)
        case staleConflict(Int64)
        case deletionConflict

        public var errorDescription: String? {
            switch self {
            case .missingConflictId:
                return "This sync conflict is missing its id. Reload conflicts and try again."
            case .conflictNotPending(let id):
                return "Sync conflict \(id) is no longer pending. Reload conflicts and try again."
            case .tableNotAllowed(let table):
                return "The conflicted table \"\(table)\" is not a synced table, so its value cannot be edited from review."
            case .invalidRecordId(let id):
                return "The conflicted record id \"\(id)\" is not valid."
            case .unknownField(let table, let field):
                return "The field \"\(field)\" no longer exists on \"\(table)\", so this conflict can only be dismissed."
            case .fieldNotTextResolvable(let table, let field):
                return "The field \"\(field)\" on \"\(table)\" is not approved for merged-text resolution."
            case .missingLiveRecord(let table, let recordId):
                return "The conflicted \"\(table)\" record \(recordId) no longer exists. Reload conflicts and try again."
            case .staleConflict(let id):
                return "Sync conflict \(id) is stale because the live value changed after it was recorded. Reload conflicts and review the newer value."
            case .deletionConflict:
                return "One side of this conflict deleted the record. Restoring a deleted record isn't supported from review yet — recreate it manually if needed."
            }
        }
    }

    /// Text fields for which a reviewer may persist an AI/device/manual String.
    /// This is intentionally narrower than the table whitelist: arbitrary text
    /// must never become a generic write primitive for financial or control data.
    private static let textResolutionFields: Set<String> = [
        "notes", "description", "content", "reason", "comment",
        "body", "summary", "instructions", "message", "details",
        "remarks", "observation",
    ]

    /// Shared field-policy check used by both conflict classification and the
    /// persistence boundary so the UI cannot offer a write the core will reject.
    public static func isTextResolutionField(_ fieldName: String) -> Bool {
        textResolutionFields.contains(fieldName.lowercased())
    }

    /// Persist an explicit merged-text choice and review the conflict atomically.
    ///
    /// The conflict row is reloaded inside the transaction, so callers cannot
    /// alter its table/field metadata. The live write, timestamp bump, audit/change
    /// log, and reviewed flag either all commit or all roll back.
    public static func applyTextConflictResolution(
        db: AppDatabase,
        conflict: ConflictLogEntry,
        selectedValue: String
    ) throws {
        guard let conflictId = conflict.id else {
            throw ConflictReviewError.missingConflictId
        }

        try db.writer.write { dbConn in
            guard let persisted = try ConflictLogEntry.fetchOne(dbConn, key: conflictId),
                  persisted.reviewed == 0 else {
                throw ConflictReviewError.conflictNotPending(conflictId)
            }
            guard isAllowedTable(persisted.tableName) else {
                throw ConflictReviewError.tableNotAllowed(persisted.tableName)
            }
            guard isTextResolutionField(persisted.fieldName) else {
                throw ConflictReviewError.fieldNotTextResolvable(
                    table: persisted.tableName,
                    field: persisted.fieldName
                )
            }
            guard let recordId = Int64(persisted.recordId) else {
                throw ConflictReviewError.invalidRecordId(persisted.recordId)
            }
            if persisted.localValue == "(DELETED)" || persisted.remoteValue == "(DELETED)" {
                throw ConflictReviewError.deletionConflict
            }

            let columns = try String.fetchAll(
                dbConn,
                sql: "SELECT name FROM pragma_table_info(?)",
                arguments: [persisted.tableName]
            )
            guard columns.contains(persisted.fieldName) else {
                throw ConflictReviewError.unknownField(
                    table: persisted.tableName,
                    field: persisted.fieldName
                )
            }

            let oldValue = try String.fetchOne(
                dbConn,
                sql: "SELECT [\(persisted.fieldName)] FROM [\(persisted.tableName)] WHERE id = ?",
                arguments: [recordId]
            )
            let exists = try Bool.fetchOne(
                dbConn,
                sql: "SELECT EXISTS(SELECT 1 FROM [\(persisted.tableName)] WHERE id = ?)",
                arguments: [recordId]
            ) ?? false
            guard exists else {
                throw ConflictReviewError.missingLiveRecord(
                    table: persisted.tableName,
                    recordId: persisted.recordId
                )
            }

            // LWW already wrote the recorded winner before review. Refuse to
            // overwrite any subsequent edit with a decision made from stale
            // conflict text. Optional equality deliberately distinguishes SQL
            // NULL from every non-NULL String; legacy "(NULL)" rows normalize to
            // the same representation as a persisted NULL.
            let recordedWinner = persisted.winner.lowercased() == "local"
                ? persisted.localValue
                : persisted.remoteValue
            let expectedLiveValue = recordedWinner == "(NULL)" ? nil : recordedWinner
            guard oldValue == expectedLiveValue else {
                throw ConflictReviewError.staleConflict(conflictId)
            }

            let normalizedSelectedValue: String? = selectedValue == "(NULL)" ? nil : selectedValue

            // Selecting the value that LWW already persisted is review-only. Do
            // not bump updated_at or create sync traffic for a semantic no-op.
            if normalizedSelectedValue == oldValue {
                try dbConn.execute(
                    sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ? AND reviewed = 0",
                    arguments: [conflictId]
                )
                guard dbConn.changesCount == 1 else {
                    throw ConflictReviewError.conflictNotPending(conflictId)
                }
                return
            }

            // Suppress generic table triggers because this transaction writes one
            // richer change entry containing both the selected and replaced text.
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")

            if columns.contains("updated_at") {
                try dbConn.execute(
                    sql: "UPDATE [\(persisted.tableName)] SET [\(persisted.fieldName)] = ?, updated_at = ? WHERE id = ?",
                    arguments: [normalizedSelectedValue, CoreFormatters.nowISO(), recordId]
                )
            } else {
                try dbConn.execute(
                    sql: "UPDATE [\(persisted.tableName)] SET [\(persisted.fieldName)] = ? WHERE id = ?",
                    arguments: [normalizedSelectedValue, recordId]
                )
            }

            let changedJSON = try jsonString([persisted.fieldName: normalizedSelectedValue ?? NSNull()])
            let oldJSON = try jsonString([persisted.fieldName: oldValue ?? NSNull()])
            try dbConn.execute(
                sql: """
                    INSERT INTO _change_log
                        (device_id, table_name, record_id, operation, changed_fields, old_values)
                    VALUES (?, ?, ?, 'UPDATE', ?, ?)
                    """,
                arguments: [
                    DeviceIdentity.current,
                    persisted.tableName,
                    recordId,
                    changedJSON,
                    oldJSON,
                ]
            )

            try dbConn.execute(
                sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ? AND reviewed = 0",
                arguments: [conflictId]
            )
            guard dbConn.changesCount == 1 else {
                throw ConflictReviewError.conflictNotPending(conflictId)
            }

            // A cleanup failure must abort and roll back the transaction. Silently
            // leaving this row behind would disable change-tracking triggers.
            try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
        }
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func valuesEquivalent(
        _ lhs: String?,
        _ rhs: String?,
        numericAffinity: Bool
    ) -> Bool {
        if lhs == rhs { return true }
        guard numericAffinity,
              let lhs,
              let rhs,
              let lhsNumber = Decimal(string: lhs),
              let rhsNumber = Decimal(string: rhs) else {
            return false
        }
        return lhsNumber == rhsNumber
    }

    /// Apply the reviewer's chosen value to the live record, then mark the
    /// conflict reviewed.
    ///
    /// LWW auto-resolution already wrote the *winner* into the row when the merge
    /// ran; the conflict log preserves both sides. Before this existed, the review
    /// UI's "keep local"/"keep remote" buttons only marked the row reviewed — the
    /// user's choice was never applied, which silently kept the LWW winner
    /// (data-loss surface found in the 2026-07-06 panel-quality audit).
    ///
    /// When the chosen side is the recorded loser, this writes it back to the
    /// record, bumps `updated_at` (when the table has one) so the manual choice
    /// wins future LWW rounds, and logs the write to `_change_log` so the decision
    /// propagates to peers. Choosing the side LWW already applied is a no-op write
    /// and just marks the conflict reviewed.
    public static func applyConflictResolution(
        db: AppDatabase,
        conflict: ConflictLogEntry,
        choice: ConflictResolutionChoice
    ) throws {
        guard let conflictId = conflict.id else {
            throw ConflictReviewError.missingConflictId
        }

        try db.writer.write { dbConn in
            guard let persisted = try ConflictLogEntry.fetchOne(dbConn, key: conflictId),
                  persisted.reviewed == 0 else {
                throw ConflictReviewError.conflictNotPending(conflictId)
            }
            guard isAllowedTable(persisted.tableName) else {
                throw ConflictReviewError.tableNotAllowed(persisted.tableName)
            }
            guard let recordId = Int64(persisted.recordId) else {
                throw ConflictReviewError.invalidRecordId(persisted.recordId)
            }
            if persisted.localValue == "(DELETED)" || persisted.remoteValue == "(DELETED)" {
                throw ConflictReviewError.deletionConflict
            }

            let columns = try String.fetchAll(
                dbConn,
                sql: "SELECT name FROM pragma_table_info(?)",
                arguments: [persisted.tableName]
            )
            guard columns.contains(persisted.fieldName) else {
                throw ConflictReviewError.unknownField(table: persisted.tableName, field: persisted.fieldName)
            }
            let declaredType = try String.fetchOne(
                dbConn,
                sql: "SELECT type FROM pragma_table_info(?) WHERE name = ?",
                arguments: [persisted.tableName, persisted.fieldName]
            )?.uppercased() ?? ""
            let numericAffinity = ["INT", "REAL", "FLOA", "DOUB", "NUM", "DEC"]
                .contains { declaredType.contains($0) }

            let oldValue = try String.fetchOne(
                dbConn,
                sql: "SELECT [\(persisted.fieldName)] FROM [\(persisted.tableName)] WHERE id = ?",
                arguments: [recordId]
            )
            let exists = try Bool.fetchOne(
                dbConn,
                sql: "SELECT EXISTS(SELECT 1 FROM [\(persisted.tableName)] WHERE id = ?)",
                arguments: [recordId]
            ) ?? false
            guard exists else {
                throw ConflictReviewError.missingLiveRecord(table: persisted.tableName, recordId: persisted.recordId)
            }

            let recordedWinner = persisted.winner.lowercased() == "local"
                ? persisted.localValue
                : persisted.remoteValue
            let expectedLiveValue = recordedWinner == "(NULL)" ? nil : recordedWinner
            guard valuesEquivalent(oldValue, expectedLiveValue, numericAffinity: numericAffinity) else {
                throw ConflictReviewError.staleConflict(conflictId)
            }

            let chosen = (choice == .keepLocal) ? persisted.localValue : persisted.remoteValue
            let writeValue: String? = chosen == "(NULL)" ? nil : chosen
            if !valuesEquivalent(writeValue, oldValue, numericAffinity: numericAffinity) {
                // Suppress generic triggers because this transaction records the
                // selected and replaced values in one richer change entry.
                try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
                if columns.contains("updated_at") {
                    try dbConn.execute(
                        sql: "UPDATE [\(persisted.tableName)] SET [\(persisted.fieldName)] = ?, updated_at = ? WHERE id = ?",
                        arguments: [writeValue, CoreFormatters.nowISO(), recordId]
                    )
                } else {
                    try dbConn.execute(
                        sql: "UPDATE [\(persisted.tableName)] SET [\(persisted.fieldName)] = ? WHERE id = ?",
                        arguments: [writeValue, recordId]
                    )
                }

                let changedJSON = try jsonString([persisted.fieldName: writeValue ?? NSNull()])
                let oldJSON = try jsonString([persisted.fieldName: oldValue ?? NSNull()])
                try dbConn.execute(
                    sql: """
                        INSERT INTO _change_log
                            (device_id, table_name, record_id, operation, changed_fields, old_values)
                        VALUES (?, ?, ?, 'UPDATE', ?, ?)
                        """,
                    arguments: [DeviceIdentity.current, persisted.tableName, recordId, changedJSON, oldJSON]
                )
            }

            try dbConn.execute(
                sql: "UPDATE _conflict_log SET reviewed = 1 WHERE id = ? AND reviewed = 0",
                arguments: [conflictId]
            )
            guard dbConn.changesCount == 1 else {
                throw ConflictReviewError.conflictNotPending(conflictId)
            }

            // Cleanup participates in the same transaction as the live write,
            // audit row, and review flag; failure rolls all of them back.
            try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
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
    /// Fix #174: if the record has unsynced local UPDATEs, log an entry to `_conflict_log`
    /// so admins can see that local edits were trumped by a remote delete (delete-always-wins
    /// policy preserved for safety, but no longer silent).
    private static func applyDelete(db: Database, change: IncomingChange, localDeviceId: String) throws {
        let table = change.tableName
        let recordId = change.recordId

        // Fix #174: Detect delete-vs-update conflicts. If we have unsynced local
        // changes for this record, log one ConflictLogEntry per affected field so
        // admins can spot this (remote delete wins, but the fact that local edits
        // were dropped is now visible).
        let localChangedFields = (try? getLocalChangedFields(
            db: db, tableName: table, recordId: recordId
        )) ?? []

        if !localChangedFields.isEmpty,
           let localRow = try getLocalRecord(db: db, tableName: table, recordId: recordId) {
            // Get local timestamp for the log entry
            let localTimestamp: String = localRow["updated_at"]
                ?? localRow["created_at"]
                ?? "1970-01-01T00:00:00Z"

            var entries: [ConflictLogEntry] = []
            for field in localChangedFields {
                let localValue = stringifyValue(localRow[field] as DatabaseValue)
                entries.append(ConflictLogEntry(
                    tableName: table,
                    recordId: recordId,
                    fieldName: field,
                    localValue: localValue,
                    remoteValue: "(DELETED)",
                    winner: "remote",   // delete always wins — document the decision
                    localDevice: localDeviceId,
                    remoteDevice: change.deviceId,
                    localTs: localTimestamp,
                    remoteTs: change.timestamp,
                    resolvedAt: currentTimestamp()
                ))
            }
            if !entries.isEmpty {
                try logConflicts(db: db, conflicts: entries)
            }
        }

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
            // Record doesn't exist locally — plain INSERT.
            //
            // NULL handling: recordDataFields is [String: String?], so a NULL
            // column is a PRESENT key with a nil inner value. The old check
            // (`if case .none = recordDataFields[key] as String??`) only matched
            // MISSING keys — present-but-NULL columns got a "?" placeholder with
            // no bound argument, and the statement threw on the argument-count
            // mismatch. The bug stayed invisible because the sender used to drop
            // any row containing a NULL before it ever reached this code
            // (see PeerManager.jsonRecordDict) — the two bugs masked each other
            // until the Bluetooth full-snapshot sync delivered real NULL rows
            // ("No User Found", 2026-07-06).
            let columns = recordDataFields.keys.sorted()
            var placeholders: [String] = []
            var values: [String] = []
            for key in columns {
                if let present = recordDataFields[key], let value = present {
                    placeholders.append("?")
                    values.append(value)
                } else {
                    placeholders.append("NULL")
                }
            }
            let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")

            try db.execute(
                sql: "INSERT OR IGNORE INTO \(quotedTable(table)) (\(columnList)) VALUES (\(placeholders.joined(separator: ", ")))",
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
                // We have full record data — INSERT it. Same present-but-NULL
                // handling as applyInsert's plain-INSERT path: a NULL column is
                // a PRESENT key with a nil inner value, and the old double-
                // optional check here only matched MISSING keys, so NULL columns
                // produced a "?" placeholder with no bound argument and the
                // statement threw (Copilot review on PR #1422 — this was the
                // second, unfixed copy of the applyInsert bug).
                let columns = recordDataFields.keys.sorted()
                var placeholders: [String] = []
                var values: [String] = []
                for key in columns {
                    if let present = recordDataFields[key], let value = present {
                        placeholders.append("?")
                        values.append(value)
                    } else {
                        placeholders.append("NULL")
                    }
                }
                let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")

                try db.execute(
                    sql: "INSERT OR IGNORE INTO \(quotedTable(table)) (\(columnList)) VALUES (\(placeholders.joined(separator: ", ")))",
                    arguments: StatementArguments(values)
                )
                return 0
            }
            // Fix #220: No local record AND no full recordData — cannot apply safely.
            // Throw a specific error so the caller can count this as skipped (not errored)
            // and trigger a full-record resync for this (table, id).
            Self.logger.info("Skipped UPDATE for missing record: table=\(table, privacy: .public) id=\(recordId) from device=\(change.deviceId, privacy: .public)")
            throw ApplyError.missingLocalRecord(table: table, recordId: recordId)
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
    ///
    /// KNOWN TRADE-OFF (#221 — row-level timestamps for per-field conflicts):
    /// LWW uses the row's `updated_at` as the comparison timestamp for ALL fields.
    /// This means a later edit to an unrelated field on device B can cause field X —
    /// where device A's change was chronologically earlier — to resolve in device B's
    /// favor. True per-field timestamps would require extending `_change_log.changed_fields`
    /// to `{field: {value, timestamp}}` and a schema migration. Deferred as a scope-bounded
    /// accepted limitation; document rather than silently surprise future contributors.
    private static func fieldLevelMerge(
        db: Database,
        table: String,
        recordId: String,
        localRow: Row,
        incomingFields: [String: String?],
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

        var mergedData: [String: String?] = [:]
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
                    remoteValue: remoteValue ?? "(NULL)",
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

        // Apply merged fields — handles NULL values correctly (fixes #196)
        if !mergedData.isEmpty {
            let sortedKeys = mergedData.keys.sorted()
            // Explicit String return type avoids GRDB SQL interpolation inference ambiguity
            let setClauses: String = sortedKeys.map { (key: String) -> String in
                if case .none = mergedData[key] as String?? {
                    return "\"\(key)\" = NULL"
                }
                return "\"\(key)\" = ?"
            }.joined(separator: ", ")
            // Only include non-nil values as bound parameters
            var args: [any DatabaseValueConvertible] = sortedKeys.compactMap { key -> String? in
                if let val = mergedData[key] { return val }
                return nil
            }
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

    /// Apply an incoming `_device_registry` change.
    ///
    /// Two things make this table special:
    /// 1. **Its primary key is `device_id` (TEXT), not `id`.** The producer
    ///    (`DeviceResetService.deactivateCurrentDevice`) therefore writes
    ///    `record_id = 0` and carries the real id inside `changed_fields`.
    /// 2. **Revocation must be monotonic.** Sync may only ever make trust
    ///    MORE restrictive: a device that has been deactivated cannot un-
    ///    deactivate or re-trust itself by pushing a row back at us. Re-
    ///    enabling a device is a deliberate local admin action, never a
    ///    replicated one — otherwise revoking a stolen device would be
    ///    undone by that same device's next sync.
    ///
    /// Returns 1 when a row was updated, 0 when there was nothing to apply.
    static func applyDeviceRegistryChange(db: Database, change: IncomingChange) throws -> Int {
        // The affected device id lives in changed_fields (preferred) or in a
        // full record payload.
        func stringField(_ json: String?, _ key: String) -> String? {
            guard let json, let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            if let s = obj[key] as? String { return s }
            if let n = obj[key] as? NSNumber { return n.stringValue }
            return nil
        }
        func intField(_ json: String?, _ key: String) -> Int? {
            guard let json, let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            if let n = obj[key] as? NSNumber { return n.intValue }
            if let s = obj[key] as? String { return Int(s) }
            return nil
        }

        let targetId = stringField(change.changedFields, "device_id")
            ?? stringField(change.recordData, "device_id")
        guard let targetId, !targetId.isEmpty else { return 0 }

        let deactivated = intField(change.changedFields, "is_deactivated")
            ?? intField(change.recordData, "is_deactivated")
        let trusted = intField(change.changedFields, "is_trusted")
            ?? intField(change.recordData, "is_trusted")

        var applied = 0
        // Monotonic revocation only: 1 -> deactivate; 0 is ignored.
        if deactivated == 1 {
            try db.execute(
                sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE device_id = ?",
                arguments: [targetId]
            )
            applied = max(applied, db.changesCount)
        }
        // Monotonic distrust only: 0 -> untrust; 1 is ignored.
        if trusted == 0 {
            try db.execute(
                sql: "UPDATE _device_registry SET is_trusted = 0 WHERE device_id = ?",
                arguments: [targetId]
            )
            applied = max(applied, db.changesCount)
        }
        return applied > 0 ? 1 : 0
    }

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
    /// NSNull values are preserved as nil to maintain SQL NULL semantics (fixes #196).
    static func parseJsonField(_ field: String?) -> [String: String?]? {
        guard let str = field, !str.isEmpty else { return nil }
        guard let data = str.data(using: .utf8) else { return nil }

        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            if let dict = obj as? [String: Any] {
                var result: [String: String?] = [:]
                for (key, value) in dict {
                    if value is NSNull {
                        result[key] = nil as String?  // preserve SQL NULL
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
    private static func currentTimestamp() -> String { CoreFormatters.iso8601Fractional.string(from: Date()) }

    /// Quote a table name to prevent SQL injection.
    private static func quotedTable(_ name: String) -> String {
        // Double-quote the table name — standard SQL quoting
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
