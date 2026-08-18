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

    /// A UNIQUE / PRIMARY KEY / rowid index refused this row's key columns
    /// because a DIFFERENT local row already owns that key (#1737).
    ///
    /// This is its OWN counter, not a reuse of `skipped`, and that is the
    /// structural point rather than a naming preference. `skipped` and `errors`
    /// are the two inputs the snapshot completeness gate THROWS on
    /// (`PeerManager.applyStagedSnapshot`'s `validate:` closure), and it runs
    /// INSIDE the write transaction — so routing a constraint outcome into
    /// either of them rolls the entire company snapshot back. #1749 did exactly
    /// that and had to be reverted: the residue is a deterministic function of
    /// (payload, local schema, local rows), so every retry re-derives it and the
    /// joiner never onboards. Counters here are named by CAUSE, never by policy,
    /// so the disposition can change later without a rename.
    public var keyCollisions: Int = 0

    /// A NOT NULL / CHECK constraint refused the row: this device's schema
    /// cannot represent what the sender sent. Distinct from `keyCollisions`
    /// because a retry can never fix it — only a schema migration can.
    public var schemaDrops: Int = 0

    /// A merge that was PARKED for the fixed-point replay was then DISCARDED
    /// unapplied, because the batch moved past it: a LATER change in the same
    /// batch WROTE the same `(table, record_id)`, or the record it was going
    /// to merge into was removed outright.
    ///
    /// "Wrote", not "arrived". A later change that was itself refused, or that
    /// carried nothing to apply, has superseded nothing — the record still holds
    /// exactly what the parked merge expected. Counting those here discarded a
    /// parked merge for no reason and lost BOTH changes.
    ///
    /// This has its own counter because it is its own CAUSE, and the two causes
    /// it is NOT are both wrong in a way that hides a bug:
    ///
    /// - It is not a `keyCollision`. A key collision is "a UNIQUE / PRIMARY KEY
    ///   / rowid index refused these values" (see above). A parked merge that is
    ///   dropped because a newer change won is a POLICY outcome about ordering,
    ///   and the index may well have accepted it. Reusing `keyCollisions` here
    ///   is exactly the "named by policy, not by cause" mistake this file argues
    ///   against everywhere else — and it made the resurrection bug below
    ///   indistinguishable from an ordinary collision in the field.
    /// - It is not `skipped` or `errors`. Those are the two gate inputs that
    ///   throw INSIDE the write transaction (#1749). This counter must never
    ///   feed either of them, no matter how bad the number looks.
    ///
    /// Non-zero here is normal and healthy: it is the count of times deferral
    /// declined to re-order a record's history.
    public var supersededMerges: Int = 0

    public init(
        applied: Int = 0,
        conflicts: Int = 0,
        skipped: Int = 0,
        errors: Int = 0,
        keyCollisions: Int = 0,
        schemaDrops: Int = 0,
        supersededMerges: Int = 0
    ) {
        self.applied = applied
        self.conflicts = conflicts
        self.skipped = skipped
        self.errors = errors
        self.keyCollisions = keyCollisions
        self.schemaDrops = schemaDrops
        self.supersededMerges = supersededMerges
    }

    /// Accumulate one change's outcome. Keeps the batched and streamed atomic
    /// apply paths tallying identically instead of by copy-paste.
    ///
    /// `errors` is deliberately absent: on the atomic paths nothing may set it,
    /// because it is a gate input that throws inside the write transaction.
    mutating func add(_ outcome: ApplyOutcome) {
        applied += outcome.applied
        conflicts += outcome.conflicts
        skipped += outcome.skipped
        keyCollisions += outcome.keyCollisions
        schemaDrops += outcome.schemaDrops
        supersededMerges += outcome.supersededMerges
    }
}

/// One change's outcome, as a struct rather than a tuple.
///
/// The type is the guard rail: a NEW outcome cannot be smuggled into an
/// EXISTING slot the way #1749 smuggled a constraint refusal into `skipped`.
/// Adding a cause means adding a field, which is visible in review.
struct ApplyOutcome: Sendable {
    var applied = 0
    var conflicts = 0
    var skipped = 0
    var keyCollisions = 0
    var schemaDrops = 0
    var supersededMerges = 0

    init(
        applied: Int = 0,
        conflicts: Int = 0,
        skipped: Int = 0,
        keyCollisions: Int = 0,
        schemaDrops: Int = 0,
        supersededMerges: Int = 0
    ) {
        self.applied = applied
        self.conflicts = conflicts
        self.skipped = skipped
        self.keyCollisions = keyCollisions
        self.schemaDrops = schemaDrops
        self.supersededMerges = supersededMerges
    }

    /// Bridge from the legacy dispatch tuple.
    ///
    /// `applyOneAtomically` still returns `(applied:conflicts:skipped:)` with
    /// its three literal `applied: 1` sites intact — making `applied` honest is
    /// a separate, gate-visible change and is deliberately NOT in this commit.
    /// This initializer is the seam where the two representations meet, and it
    /// disappears when that change lands.
    init(_ legacy: (applied: Int, conflicts: Int, skipped: Int)) {
        self.init(applied: legacy.applied, conflicts: legacy.conflicts, skipped: legacy.skipped)
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
                let outcome = try db.writer.write { dbConn -> ApplyOutcome in
                    // One context per row, because one TRANSACTION per row: this
                    // path has no batch to replay a collision against, so a
                    // collision is resolved (or given up on) immediately. See
                    // `ApplyContext.Disposition.perRow` — the asymmetry with the
                    // batched paths is deliberate.
                    let context = ApplyContext(disposition: .perRow)

                    // Echo guard: while this transaction applies a PEER's change,
                    // the change-tracking triggers (migration 112) must not log
                    // the write — otherwise every applied change would be re-
                    // pushed back to the peer forever. The guard row lives only
                    // inside this transaction (rolled back with it on failure).
                    try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")

                    let outcome: ApplyOutcome

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
                        return ApplyOutcome(applied: applied, skipped: applied == 1 ? 0 : 1)
                    }

                    switch change.operation.uppercased() {
                    case "DELETE":
                        try applyDelete(db: dbConn, change: change, localDeviceId: localDevice)
                        outcome = ApplyOutcome(applied: 1)

                    case "INSERT":
                        let conflictCount = try applyInsert(
                            db: dbConn, change: change, localDeviceId: localDevice, context: context
                        )
                        outcome = ApplyOutcome(applied: 1, conflicts: conflictCount)

                    case "UPDATE":
                        let conflictCount = try applyUpdate(
                            db: dbConn, change: change, localDeviceId: localDevice, context: context
                        )
                        outcome = ApplyOutcome(applied: 1, conflicts: conflictCount)

                    default:
                        outcome = ApplyOutcome(skipped: 1)
                    }

                    // Cleanup participates in the transaction: failure rolls back
                    // the peer write instead of silently disabling local tracking.
                    try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")

                    // Residue rides back inside the transaction's own return
                    // value: if this row's write rolls back, its residue is
                    // discarded with it rather than being counted for a change
                    // that left no trace.
                    var combined = outcome
                    let residue = context.residue()
                    combined.conflicts += residue.conflicts
                    combined.keyCollisions += residue.keyCollisions
                    combined.schemaDrops += residue.schemaDrops
                    // Always zero on this path — nothing may be parked here, so
                    // nothing can be superseded — but summed rather than assumed,
                    // so the two paths stay structurally identical.
                    combined.supersededMerges += residue.supersededMerges
                    return combined
                }
                result.add(outcome)
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
    /// This is the **ongoing multipeer delta** door (#1684), not the snapshot door.
    /// Reporting an apply failure while retaining a successful prefix would leave a
    /// peer holding a partially-merged batch it believes was rejected, so the whole
    /// batch rolls back. The best-effort API above (`resolveAndApplyChanges`) keeps
    /// the per-row contract for the LAN/pull path.
    ///
    /// Initial Bluetooth snapshots do **not** reach here. Since WEI-7022 they are
    /// staged durably and applied by the streaming twin
    /// `resolveAndApplyStreamedChangesAtomically` via `PeerManager.applyStagedSnapshot`.
    /// Sole caller: `PeerManager.applyIncomingChanges`, reached from the two `else`
    /// branches of `if snapshotStagingPeers.contains(...)`.
    static func resolveAndApplyChangesAtomically(
        db: AppDatabase,
        changes: [IncomingChange],
        localDeviceId: String? = nil
    ) throws -> MergeResult {
        let localDevice = localDeviceId ?? DeviceIdentity.current

        return try db.writer.write { dbConn in
            var result = MergeResult()
            try deferForeignKeysForThisTransaction(dbConn)
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            defer { try? dbConn.execute(sql: "DELETE FROM _sync_apply_guard") }

            // Lift BEFORE any row is applied: a reordered stage list is a
            // permutation of a unique key and has no valid row-at-a-time
            // ordering. See `suspendJobStageSortIndex`.
            //
            // This also fixes the moment at which `ApplyContext`'s unique-column
            // cache may first be read: it is populated LAZILY, from the live
            // database, so every answer it gives is taken with this index
            // genuinely absent. Reading it before the drop would make the ladder
            // withhold `job_stages.sort_order` and silently break the #1729
            // permutation path.
            let sortIndexDDL = try suspendJobStageSortIndex(dbConn)
            let context = ApplyContext(disposition: .batched)

            for change in changes {
                result.add(ApplyOutcome(try applyOneAtomically(dbConn, change, localDevice, context)))
            }

            // Between the last row and the restore: the replay needs the same
            // suspended-index conditions the first pass had.
            try drainDeferredMerges(dbConn, context)
            result.add(context.residue())

            try restoreJobStageSortIndex(dbConn, capturedDDL: sortIndexDDL)

            return result
        }
    }

    /// Hold foreign-key checking until COMMIT for the duration of this
    /// transaction (#1728).
    ///
    /// The host streams snapshot tables in **creation** order —
    /// `SELECT name FROM sqlite_master … ORDER BY rowid` (`PeerManager.swift`)
    /// — which is the order 124 migrations happened to create them, not a
    /// topological order of the foreign-key graph. Nine child→parent edges are
    /// inverted, so a child row routinely arrives before its parent: a job
    /// notebook before `notebook_templates`, a notebook section before its
    /// group, a labor entry before the to-do it links to.
    ///
    /// That is fatal rather than merely untidy, because of three facts that
    /// only bite together:
    ///
    /// 1. Foreign keys are ENFORCED — `config.foreignKeysEnabled = true` on
    ///    every connection this app opens.
    /// 2. `INSERT OR IGNORE` does NOT suppress a FOREIGN KEY violation.
    ///    SQLite's ON CONFLICT algorithms cover UNIQUE / NOT NULL / CHECK / PK
    ///    only, so the insert branch cannot absorb it.
    /// 3. `applyOneAtomically` deliberately catches only
    ///    `ApplyError.missingLocalRecord`, so the error escapes
    ///    `db.writer.write` and rolls the ENTIRE company snapshot back.
    ///
    /// One out-of-order row therefore killed the whole join, deterministically,
    /// on every retry — the same shape as #1723 and the next blocker behind it.
    ///
    /// Deferring is preferred over topologically sorting the send: sorting is a
    /// far larger change, has to reason about cycles across 459 FK edges, and
    /// protects only the send path, whereas this protects the apply no matter
    /// who is sending. The pragma is transaction-scoped and resets itself at
    /// COMMIT, so it cannot leak into ordinary writes.
    ///
    /// This does NOT weaken the constraint. Every FK is still checked, just at
    /// COMMIT instead of per-statement: a snapshot with a genuinely orphaned
    /// row (parent hard-deleted on the host) still fails and still rolls back.
    /// It only stops *arrival order* from being mistaken for corruption.
    private static func deferForeignKeysForThisTransaction(_ dbConn: Database) throws {
        try dbConn.execute(sql: "PRAGMA defer_foreign_keys = ON")
    }

    /// The one unique index in the schema whose key a user can *permute* (#1729).
    private static let jobStageSortIndexName = "idx_job_stages_template_sort_active"

    /// Lift the job-stage ordering index for the duration of an apply, returning
    /// the DDL needed to put it back (#1729).
    ///
    /// `job_stages` carries
    /// `UNIQUE(template_id, sort_order) WHERE deleted_at IS NULL`, and its rows
    /// 1–3 are migration-seeded with the SAME ids on every device
    /// (`AppDatabase+Migrations.swift`: seeded, then backfilled onto a `Default`
    /// template). Identical ids are precisely the property that routes a row
    /// AWAY from the `INSERT OR IGNORE` branch and onto the merge branch — whose
    /// `UPDATE … WHERE id = ?` carries no conflict clause. So a host that merely
    /// *reordered* its stage list ships a permutation of a UNIQUE key, and a
    /// permutation cannot be written one row at a time: the first row to move
    /// into an occupied slot throws, and the whole company snapshot rolls back.
    ///
    /// The product code already knows this is impossible —
    /// `JobsService.reorderJobStages` writes every stage to a NEGATIVE
    /// `sort_order` scratch value first, purely to avoid transiently colliding on
    /// this index. Sync did the naive thing. That asymmetry was the bug.
    ///
    /// `PRAGMA defer_foreign_keys` (the #1728 fix) cannot help: SQLite has no
    /// deferrable UNIQUE, and `UNIQUE(a,b) DEFERRABLE INITIALLY DEFERRED` is a
    /// parse error. Drop-and-recreate is the only mechanism the engine offers.
    ///
    /// **This must be called with nothing in flight on `dbConn`.** `DROP INDEX`
    /// emits `OP_Destroy`, whose guard is connection-wide (`db->nVdbeRead`), so
    /// ANY partially-consumed statement — even a cursor over an unrelated table —
    /// makes it fail with "database table is locked". `CREATE INDEX` emits no
    /// `OP_Destroy` and is immune, which is why `restoreJobStageSortIndex` may
    /// safely run while the streaming producer's cursor is still open but this
    /// may not. Callers therefore drop at the TOP of the transaction, before any
    /// producer runs.
    ///
    /// Returns `nil` when the index is absent — a database that predates the
    /// migration creating it is legitimate, and failing there would newly break
    /// the exact join path this exists to unbreak. `sql IS NOT NULL` also
    /// mechanically excludes constraint-backed `sqlite_autoindex_*` entries,
    /// which cannot be dropped and have no DDL text to replay.
    private static func suspendJobStageSortIndex(_ dbConn: Database) throws -> String? {
        // Captured VERBATIM and before the drop: `sqlite_master` loses the row
        // the moment we drop, and SQLite stores the submitted text
        // uncanonicalized. Re-typing the statement is how the partial
        // `WHERE deleted_at IS NULL` predicate silently becomes a TOTAL unique
        // index that starts rejecting soft-deleted duplicates.
        guard let ddl = try String.fetchOne(
            dbConn,
            sql: """
                SELECT sql FROM sqlite_master
                WHERE type = 'index' AND name = ? AND sql IS NOT NULL
                """,
            arguments: [jobStageSortIndexName]
        ) else {
            // No DDL to put back, so nothing may be taken away.
            return nil
        }

        try dbConn.execute(sql: "DROP INDEX IF EXISTS \(jobStageSortIndexName)")
        return ddl
    }

    /// Put the job-stage ordering index back, reconciling first so it can (#1729).
    ///
    /// Must run only once every change in the batch has landed — the intermediate
    /// states are exactly what the index cannot represent.
    private static func restoreJobStageSortIndex(
        _ dbConn: Database,
        capturedDDL: String?
    ) throws {
        guard let ddl = capturedDDL else { return }

        try reconcileJobStageSortOrders(dbConn)

        // Replay the captured text, never a literal. If the reconciliation ever
        // misses a case this throws, the transaction rolls back, and the index
        // returns with full enforcement — which is the correct outcome: a
        // snapshot that cannot satisfy the constraint must not land. Never
        // soften this to `try?`; committing without the index would silently and
        // permanently lose the invariant on this device, with no migration that
        // would ever restore it.
        try dbConn.execute(sql: ddl)
    }

    /// Make `job_stages` satisfiable by its ordering index again (#1729).
    ///
    /// With the index lifted, a PARTIALLY delivered reorder can leave two live
    /// rows in one `(template_id, sort_order)` slot — the host ships id 1 into
    /// slot 3 while this device's id 3 still holds slot 3. Recreating over that
    /// state throws, which would merely relocate the total rollback from the
    /// `UPDATE` to the `CREATE`. This pass is what makes the recreate safe, so it
    /// is load-bearing rather than defensive.
    ///
    /// Renumbering is deliberate; soft-deleting the loser is NOT an option here.
    /// `JobsService.archiveJobStage` refuses to soft-delete a stage referenced by
    /// an active job, a JPO line item, or a category mapping, and this would
    /// bypass that guard from underneath. Worse, a soft-deleted stage that a job
    /// still points at makes `OrdersService.markStageComplete` throw
    /// `stageNotFound`, so the job could never advance — strictly worse than the
    /// bug being fixed. Renumbering deletes nothing and keeps every foreign-key
    /// referent live.
    ///
    /// Deliberately a pure function of the FINAL row set, ordered only by
    /// `(sort_order, id)`. These writes happen under `_sync_apply_guard`, so the
    /// change-tracking triggers do not fire and the renumber NEVER reaches the
    /// peer. Two devices can only agree if each computes the same answer from the
    /// same rows, which rules out any "which rows came from the peer" input and
    /// any dependence on physical row order. `id` is the sync record key, so it
    /// is the one column guaranteed to mean the same thing on both sides. This is
    /// the same tie-break the migration that created the index already chose, so
    /// the repair sync performs and the repair the migration performed cannot
    /// disagree.
    private static func reconcileJobStageSortOrders(_ dbConn: Database) throws {
        // `template_id IS NOT NULL` is correctness, not tuning: SQLite treats
        // NULLs as DISTINCT in a unique index, so NULL-template rows can never
        // violate it — but `GROUP BY` *does* fold NULLs together and would
        // report them as duplicates and renumber rows that were fine.
        //
        // Self-gating: with no collision, `colliding` is empty, so `ordered` is
        // empty and the UPDATE touches zero rows. Templates that are already
        // consistent are left byte-identical.
        //
        // `ROW_NUMBER() … PARTITION BY template_id` is injective over a
        // template, so the result cannot collide no matter what order SQLite
        // evaluates the rows in — correct by construction rather than by
        // observed engine behaviour.
        //
        // `updated_at` is intentionally NOT bumped: this is a local repair, not
        // a user edit, and `updated_at` is the row's LWW comparison timestamp.
        // Bumping it would let an unrelated genuinely-unsynced local field start
        // winning against the peer.
        try dbConn.execute(sql: """
            WITH colliding AS (
                SELECT template_id
                FROM job_stages
                WHERE deleted_at IS NULL AND template_id IS NOT NULL
                GROUP BY template_id, sort_order
                HAVING COUNT(*) > 1
            ),
            ordered AS (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY template_id ORDER BY sort_order ASC, id ASC
                       ) AS normalized_sort_order
                FROM job_stages
                WHERE deleted_at IS NULL
                  AND template_id IS NOT NULL
                  AND template_id IN (SELECT template_id FROM colliding)
            )
            UPDATE job_stages
            SET sort_order = (
                    SELECT normalized_sort_order FROM ordered WHERE ordered.id = job_stages.id
                )
            WHERE id IN (SELECT id FROM ordered)
            """)
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
    /// - Parameter validate: Caller's completeness rule, run INSIDE the
    ///   transaction once every change has been applied. It must be here
    ///   rather than at the call site: a rule that throws after `write`
    ///   returns is checking a transaction that has already committed, so it
    ///   can report a bad outcome but cannot undo one. Throwing from here rolls
    ///   the whole snapshot back, which is the only useful response to
    ///   "this did not fully land".
    static func resolveAndApplyStreamedChangesAtomically(
        db: AppDatabase,
        localDeviceId: String? = nil,
        produceChanges: (Database, (IncomingChange) throws -> Void) throws -> Void,
        validate: ((MergeResult) throws -> Void)? = nil
    ) throws -> MergeResult {
        let localDevice = localDeviceId ?? DeviceIdentity.current

        return try db.writer.write { dbConn in
            var result = MergeResult()
            // See `deferForeignKeysForThisTransaction`. This is the path the
            // real Bluetooth join takes, so it is the one that was dying.
            try deferForeignKeysForThisTransaction(dbConn)
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            defer { try? dbConn.execute(sql: "DELETE FROM _sync_apply_guard") }

            // Must precede `produceChanges`: that closure holds a cursor open on
            // THIS connection for the whole apply, and `DROP INDEX` fails while
            // any statement is in flight. See `suspendJobStageSortIndex`.
            //
            // It also fixes the earliest moment `ApplyContext`'s unique-column
            // cache can be populated. That cache is LAZY precisely so every
            // answer is read with this index already dropped; building it any
            // earlier would let the ladder withhold `job_stages.sort_order` and
            // silently break the #1729 permutation path.
            let sortIndexDDL = try suspendJobStageSortIndex(dbConn)
            let context = ApplyContext(disposition: .batched)

            try produceChanges(dbConn) { change in
                result.add(ApplyOutcome(try applyOneAtomically(dbConn, change, localDevice, context)))
            }

            // Between the producer finishing and the restore. The replay must
            // see the index still suspended, and it runs no DDL of its own —
            // the producer's cursor may still be open on this connection.
            try drainDeferredMerges(dbConn, context)
            result.add(context.residue())

            // Safe here even though the producer's cursor may still be open:
            // `CREATE INDEX` is not subject to the in-flight-statement rule that
            // constrains the drop above.
            try restoreJobStageSortIndex(dbConn, capturedDDL: sortIndexDDL)

            try validate?(result)

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
        _ localDeviceId: String,
        _ context: ApplyContext
    ) throws -> (applied: Int, conflicts: Int, skipped: Int) {
        // BEFORE the table guard and before any dispatch: what is being counted
        // is this change's POSITION in the batch, and a rejected row still
        // occupies one. A hole in the count would make an entry parked after it
        // look older than it is. See `ApplyContext.noteChangeArriving`.
        //
        // This counts the position and NOTHING else. Whether this change may
        // supersede a parked merge is decided by whether it actually writes,
        // which only the write sites know — see `ApplyContext.noteRecordMutated`.
        context.noteChangeArriving()

        guard isAllowedTable(change.tableName) else { return (0, 0, 1) }

        do {
            switch change.operation.uppercased() {
            case "DELETE":
                // The one write site not reached through `context`: `applyDelete`
                // is shared with the per-row path and takes no context, so it
                // reports whether it removed anything and the caller records it.
                let removed = try applyDelete(db: dbConn, change: change, localDeviceId: localDeviceId)
                if removed {
                    context.noteRecordMutated(table: change.tableName, recordId: change.recordId)
                }
                return (1, 0, 0)
            case "INSERT":
                let conflictCount = try applyInsert(
                    db: dbConn,
                    change: change,
                    localDeviceId: localDeviceId,
                    context: context
                )
                return (1, conflictCount, 0)
            case "UPDATE":
                let conflictCount = try applyUpdate(
                    db: dbConn,
                    change: change,
                    localDeviceId: localDeviceId,
                    context: context
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

    // MARK: - Private: Row-Level Constraint Refusals (#1737)

    /// How SQLite refused ONE row's write. Classified from the extended result
    /// code, never guessed from `changesCount` — both classes report zero rows
    /// changed, so a count cannot separate them.
    enum WriteRefusal: Sendable {
        /// UNIQUE / PRIMARY KEY / rowid: a DIFFERENT local row already owns this
        /// key. Possibly recoverable — the row holding the slot may itself move
        /// later in the same batch (see the fixed-point replay).
        case keyCollision
        /// NOT NULL / CHECK: this device's schema cannot represent the row.
        /// Never recoverable by retrying — only a migration changes the answer.
        case schemaDrop
    }

    /// Execute `body`; CLASSIFY a row-level constraint refusal and return it
    /// instead of throwing. Everything else propagates completely unchanged.
    ///
    /// The `default: throw` arm is the load-bearing half. Foreign-key ordering,
    /// `noSuchTable`, SQLITE_MISUSE, I/O errors and trigger aborts must still
    /// roll the caller's transaction back exactly as they do at HEAD — this
    /// helper narrows the blast radius of two specific classes, it does not turn
    /// the apply into a swallow-everything loop.
    ///
    /// The five codes are listed individually and the PRIMARY code
    /// `.SQLITE_CONSTRAINT` is deliberately NOT matched: GRDB gives `ResultCode`
    /// a custom `~=` under which a primary pattern matches every one of its
    /// extended codes, so `case .SQLITE_CONSTRAINT` would silently absorb
    /// FOREIGNKEY and TRIGGER too.
    ///
    /// **No savepoint.** A statement-level constraint ABORT undoes only that
    /// statement; it does not set `sqlite3_get_autocommit`, which is the only
    /// condition under which GRDB declares a transaction dead
    /// (`Database.checkForAbortedTransaction`). The transaction stays usable,
    /// an open cursor on the same connection keeps delivering rows, and later
    /// writes still commit. `ConflictResolverNaturalKeyTests`' T-12 proves that
    /// through GRDB on the real streamed path rather than by assertion.
    ///
    /// One caveat worth recording: GRDB's failure path calls
    /// `observationBroker?.statementDidFail` before throwing, which would tell a
    /// registered `TransactionObserver` the transaction rolled back. This module
    /// registers none today; if one is ever added, revisit this.
    private static func classifyingRowRefusal(_ body: () throws -> Void) rethrows -> WriteRefusal? {
        do {
            try body()
            return nil
        } catch let error as DatabaseError {
            switch error.extendedResultCode {
            case .SQLITE_CONSTRAINT_UNIQUE,
                 .SQLITE_CONSTRAINT_PRIMARYKEY,
                 .SQLITE_CONSTRAINT_ROWID:
                return .keyCollision
            case .SQLITE_CONSTRAINT_NOTNULL,
                 .SQLITE_CONSTRAINT_CHECK:
                return .schemaDrop
            default:
                throw error
            }
        }
    }

    /// Columns of `table` that participate in ANY unique index, read from the
    /// LIVE database rather than from migration source.
    ///
    /// Source is not an option: the migrated schema holds 82 non-PK unique
    /// indexes, 67 of which are inline-DSL column/table constraints that
    /// materialise as `sqlite_autoindex_*` and are invisible to a
    /// `CREATE UNIQUE INDEX` grep.
    ///
    /// Two deliberate limits, both of which the give-up rung of the merge ladder
    /// exists to cover:
    ///
    /// 1. **A partial index's PREDICATE columns are invisible here.**
    ///    `pragma_index_info` reports only the KEY columns, so for
    ///    `ON job_stage_templates(is_default) WHERE is_default = 1 AND
    ///    archived_at IS NULL` it returns `is_default` alone. Writing
    ///    `archived_at = NULL` moves a row INTO that index, and nothing in this
    ///    enumeration can see it. No predicate is parsed — a parser would be
    ///    false comfort, since it would still have to reimplement SQLite's index
    ///    semantics to be trusted.
    /// 2. **Expression indexes report a NULL column name** (`cid = -2`). Those
    ///    rows are skipped; coercing a NULL into a column name would crash on
    ///    the next `localRow[field]` subscript.
    ///
    /// A `TEXT PRIMARY KEY` table's `sqlite_autoindex_*` (origin `pk`) is
    /// included, on purpose: it is a real unique key. It is harmless on the
    /// merge path, which never merges `id` at all.
    ///
    /// `pragma_index_list` is used rather than GRDB's `db.indexes(in:)` for the
    /// same reason `applyDelete` prefers `pragma_table_info`: the pragma returns
    /// zero rows for a table this device does not have, while the GRDB API
    /// THROWS `noSuchTable` — and a throw here would roll back the whole company
    /// snapshot, which is the exact failure class this change removes.
    static func uniqueParticipatingColumns(_ db: Database, _ table: String) throws -> Set<String> {
        // `unique` is a reserved word and MUST stay double-quoted.
        let uniqueIndexNames = try String.fetchAll(
            db,
            sql: """
                SELECT name FROM pragma_index_list(?) WHERE "unique" = 1
                """,
            arguments: [table]
        )

        var columns = Set<String>()
        for indexName in uniqueIndexNames {
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM pragma_index_info(?)",
                arguments: [indexName]
            )
            // `compactMap`, never a forced `as String`: an expression index's
            // column name comes back NULL.
            columns.formUnion(rows.compactMap { $0["name"] as String? })
        }
        return columns
    }

    /// A merge UPDATE that a unique index refused and that may be worth retrying
    /// once the rest of the batch has landed.
    struct DeferredMerge {
        let table: String
        let recordId: String
        let incomingFields: [String: String?]
        let change: IncomingChange
        let localDeviceId: String
        /// This change's POSITION in the batch, assigned on arrival.
        ///
        /// Load-bearing, not diagnostic. Deferral moves a change to the END of
        /// the batch, so without a record of where it came from there is no way
        /// to tell "replaying this is the ordering fix the fixed point exists
        /// for" from "replaying this undoes every later change to the same
        /// record". See `ApplyContext.isSuperseded`.
        let arrivalOrdinal: Int
        /// Rough retained size, used only to bound the buffer.
        let approximateBytes: Int
    }

    /// State that lives exactly as long as ONE apply, and no longer.
    ///
    /// Deliberately an instance threaded through the call chain rather than a
    /// `static var`. On the BATCHED paths `suspendJobStageSortIndex` DROPS a
    /// unique index for the duration of the apply, so the answer to "which
    /// columns are unique here" is only valid inside that window; a
    /// process-global cache would serve a later apply a schema snapshot taken
    /// while an index was missing (or be poisoned by one taken while it was
    /// present). It would also be shared mutable state under Swift 6
    /// concurrency checking.
    ///
    /// **The suspension is NOT a global invariant, and nothing here should be
    /// read as if it were.** `resolveAndApplyChanges` — the per-row delta path —
    /// never suspends anything, so on that path the enumeration DOES report
    /// `job_stages.sort_order` and the ladder's attempt 2 will withhold it. The
    /// consequence is a half-merged `job_stages` row plus a `_conflict_log` row
    /// recording `winner: "local"` for a field no user edited locally — it was a
    /// constraint refusal, not an edit. That is a real (if narrow) defect and is
    /// deliberately NOT fixed in this commit: the candidate fixes are running
    /// DDL inside every delta transaction, or teaching the enumeration which
    /// index is currently suspended, and both are behaviour changes to the delta
    /// path with their own test surface.
    final class ApplyContext {
        /// Whether a key collision may be parked and retried later.
        enum Disposition {
            /// One transaction for the whole batch: a row that collides now may
            /// stop colliding once a later row vacates the slot, so park it and
            /// replay after the batch (§6 fixed point).
            case batched
            /// One transaction PER ROW (`resolveAndApplyChanges`): there is no
            /// later row inside this transaction and no batch to replay, so a
            /// collision is resolved or recorded immediately. This asymmetry is
            /// deliberate, not an oversight.
            case perRow
        }

        let disposition: Disposition

        /// Set while the deferral buffer is being drained: collisions must then
        /// resolve in place instead of re-parking forever.
        var isDraining = false

        private var uniqueColumnCache: [String: Set<String>] = [:]
        private var deferred: [DeferredMerge] = []
        private var deferredBytes = 0

        /// Position of the change currently being applied, counting from 1.
        ///
        /// A batch is the raw `_change_log` ordered by timestamp/sequence —
        /// `ChangeTracker.getPendingChanges` / `changesSince` do NO per-record
        /// dedup — so SEVERAL changes to one record in one batch is the normal
        /// shape, and their order is the entire correctness mechanism:
        /// `fieldLevelMerge` accepts a remote value unconditionally whenever the
        /// field is not in `getLocalChangedFields`, so within a batch arrival
        /// order, not the timestamp, is the arbiter.
        private(set) var arrivalOrdinal = 0

        /// Set while ONE parked entry is being replayed, so that a re-park keeps
        /// the entry's ORIGINAL position instead of picking up the counter's
        /// current (end-of-batch) value. Without this, surviving one replay pass
        /// would silently promote an entry to "newest change to this record".
        private var replayingArrivalOrdinal: Int?

        /// Highest arrival ordinal at which this batch actually WROTE a record,
        /// kept ONLY for records that have been parked at least once.
        ///
        /// "Wrote", not "arrived", and the distinction is the whole correctness
        /// of the supersession rule — see `noteRecordMutated`.
        ///
        /// Deliberately not a journal of the whole batch: a company snapshot is
        /// hundreds of thousands of rows and this is the one component that
        /// holds per-row state on a phone. Keying it on parks bounds it by
        /// `maxDeferredEntries`, and a record that never parked can never have a
        /// parked entry to supersede.
        private var latestArrivalOrdinal: [String: Int] = [:]

        /// Residue that never reaches `skipped` or `errors`.
        var keyCollisions = 0
        var schemaDrops = 0
        /// Parked merges DISCARDED because a later change in the same batch
        /// superseded them. See `MergeResult.supersededMerges`.
        var supersededMerges = 0
        /// Conflict-log entries written during the drain, which happens after
        /// the per-change outcome has already been tallied.
        var replayConflicts = 0

        /// Hard caps. This is the only component that holds decoded rows in
        /// memory during a whole-company snapshot on a phone, and an iOS jetsam
        /// kill looks exactly like the failure this change exists to fix.
        static let maxDeferredEntries = 5_000
        static let maxDeferredBytes = 8 * 1024 * 1024
        static let maxReplayPasses = 4

        init(disposition: Disposition) {
            self.disposition = disposition
        }

        var canDefer: Bool { disposition == .batched && !isDraining }
        var hasDeferredWork: Bool { !deferred.isEmpty }
        var deferredCount: Int { deferred.count }

        /// The position a merge parked RIGHT NOW should carry.
        var ordinalForParking: Int { replayingArrivalOrdinal ?? arrivalOrdinal }

        /// The identity this rule keys on: the ROW a change resolves to, not the
        /// spelling the peer used to name it.
        ///
        /// `IncomingChange` is peer-controlled wire input, and two spellings of
        /// one row reach the SAME row on the way to the database:
        ///
        /// - **Table.** `isAllowedTable` matches `name.lowercased()` against the
        ///   whitelist, so `Part_Categories` passes the guard, and SQLite
        ///   identifiers are case-insensitive, so its `UPDATE` hits the same
        ///   table. That `.lowercased()` is the codebase already expecting
        ///   case-variant table names on this exact dispatch path.
        /// - **Record id.** The apply binds `WHERE id = ?`, and SQLite's INTEGER
        ///   column affinity converts the text before comparing — so `'05'`
        ///   updates row 5. Canonicalising through `Int64` mirrors that. An id
        ///   that does not parse as an integer keeps its RAW spelling (not the
        ///   trimmed one), which is what a TEXT key needs.
        ///
        /// Without both, a later change spelled differently writes the record,
        /// `isSuperseded` looks up a key nobody stored, and the parked merge
        /// replays over it — the original #1737 defect, verbatim.
        ///
        /// **Measured residual, recorded rather than guessed.** Against
        /// `id INTEGER PRIMARY KEY` holding row 5, `WHERE id = ?` matches for
        /// `'5'`, `'05'`, `'005'`, `'+5'`, `' 5'`, `'5 '`, `'\n5'`, `'\t5'`,
        /// `'5.0'` and `'5e0'`, and does NOT match for `'0x5'`. Integer and
        /// whitespace-padded forms are handled here; the two DECIMAL-FLOAT
        /// spellings are not, because covering them means reimplementing
        /// SQLite's numeric-literal grammar — the same false comfort this file
        /// refuses for partial-index predicates. A change spelled `'5.0'`
        /// therefore still keys separately, and the consequence is exactly the
        /// pre-fix behaviour for that one spelling: the parked merge replays
        /// over it. Shipped producers emit `NEW.id`, an integer.
        ///
        /// U+0001 cannot occur in a table name (every key is built after
        /// `isAllowedTable`, so the table came from `allowedSyncTables`) and so
        /// cannot forge a key boundary.
        private static func recordKey(_ table: String, _ recordId: String) -> String {
            // `.whitespacesAndNewlines`, not `.whitespaces`: SQLite's conversion
            // skips a leading newline or tab too, and both were measured above.
            let trimmed = recordId.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalId = Int64(trimmed).map(String.init) ?? recordId
            return "\(table.lowercased())\u{1}\(canonicalId)"
        }

        /// Announce that the NEXT change in the batch is about to be applied.
        ///
        /// Must be called for EVERY change on a batched path — including
        /// DELETEs, unknown operations and disallowed tables — because the thing
        /// being counted is position in the batch, and a hole in the count is a
        /// silent mis-ordering.
        ///
        /// It deliberately does NOT refresh `latestArrivalOrdinal`. Arriving is
        /// not writing, and three shapes reach this line and then write nothing
        /// at all: a merge refused by NOT NULL/CHECK (`schemaDrop`), a change
        /// carrying an operation verb this device does not recognise, and an
        /// UPDATE with neither `changed_fields` nor `record_data`. Treating any
        /// of those as a supersession discarded a parked merge that nothing had
        /// superseded, and BOTH changes were then lost permanently — the discard
        /// runs under `_sync_apply_guard`, so nothing is re-broadcast, and the
        /// peer's watermark advances regardless. See `noteRecordMutated`.
        func noteChangeArriving() {
            arrivalOrdinal += 1
        }

        /// Record that the change being applied RIGHT NOW actually WROTE
        /// `table`/`recordId`. This is the only event that may supersede a
        /// parked merge.
        ///
        /// Call it from the write sites, after the statement succeeded and only
        /// when it changed at least one row — never from the dispatcher, which
        /// cannot tell a write from a refusal.
        ///
        /// The position used is `ordinalForParking`, so a write performed by a
        /// REPLAYED entry is attributed to that entry's ORIGINAL batch position
        /// rather than to the end of the batch — the same rule a re-park obeys,
        /// and for the same reason. `max` keeps the recorded position monotone.
        func noteRecordMutated(table: String, recordId: String) {
            let key = Self.recordKey(table, recordId)
            // Only records that have already parked are tracked; see
            // `latestArrivalOrdinal`.
            guard let known = latestArrivalOrdinal[key] else { return }
            latestArrivalOrdinal[key] = max(known, ordinalForParking)
        }

        /// Has a LATER change in this batch made replaying `entry` a rewrite of
        /// history rather than a repair of ordering?
        ///
        /// The whole point of the fixed point is that a merge which collided at
        /// position k may succeed once the row holding the slot moves. What it
        /// must NOT do is apply position k's payload after position k+n has
        /// already been applied to the same record — that resurrects a record a
        /// later DELETE removed, and lets an older field value overwrite a newer
        /// one (which also clobbers `updated_at`, the LWW authority for every
        /// FUTURE merge of that row). Neither is visible in any counter, because
        /// the replay SUCCEEDS, and neither is re-broadcast, because the replay
        /// runs under `_sync_apply_guard` — the two devices simply diverge
        /// forever.
        ///
        /// A DELETE arriving LATER supersedes through exactly this rule, since a
        /// DELETE that removes the row is a write like any other. A DELETE
        /// arriving EARLIER than the parked merge deliberately does not: the
        /// merge is genuinely the newer change there, and replaying it is what
        /// an in-order apply would have done anyway.
        ///
        /// Only a change that WROTE the record counts (`noteRecordMutated`).
        /// A later change that wrote nothing has superseded nothing: the record
        /// still holds exactly the value the parked merge expected to find, so
        /// replaying it repairs the ordering instead of rewriting history.
        func isSuperseded(_ entry: DeferredMerge) -> Bool {
            supersedingWriteOrdinal(entry) != nil
        }

        /// The batch position of the later write that superseded `entry`, for
        /// the discard log. `nil` when nothing superseded it.
        func supersedingWriteOrdinal(_ entry: DeferredMerge) -> Int? {
            let key = Self.recordKey(entry.table, entry.recordId)
            guard let latest = latestArrivalOrdinal[key],
                  latest > entry.arrivalOrdinal else { return nil }
            return latest
        }

        /// Park a collided merge. Returns `false` when a cap is hit — the caller
        /// then resolves it in place. Overflow NEVER throws.
        func enqueueDeferredMerge(_ entry: DeferredMerge) -> Bool {
            guard deferred.count < Self.maxDeferredEntries,
                  deferredBytes + entry.approximateBytes <= Self.maxDeferredBytes else {
                return false
            }
            deferred.append(entry)
            deferredBytes += entry.approximateBytes
            // START tracking this record — and ONLY start. A park must never
            // REFRESH an ordinal that is already there, because a park is not a
            // write, and this rule admits no exception for it either.
            //
            // Insert-if-absent, for three reasons:
            //
            // 1. Two parked entries need NO supersession between them.
            //    `takeDeferred()` hands them back in APPEND order, which is
            //    arrival order, so replaying both in sequence IS the in-order
            //    result. Refreshing prevented no re-ordering whatsoever; all it
            //    did was discard the earlier entry, and the record then held
            //    NEITHER payload whenever the later one resolved to a rung that
            //    writes nothing — `reduced.isEmpty` and the attempt-3 give-up in
            //    `resolveKeyCollisionInPlace` both return without running a
            //    statement against the merged record. (`reduced.isEmpty` does
            //    still run `logConflicts`, which INSERTs into `_conflict_log`;
            //    that is a record OF the collision, never a write to the row.)
            //    Nor is a write-nothing rung the only shape that loses data: when
            //    the reduction leaves a NON-empty SET clause each entry writes a
            //    different subset of columns, so discarding the earlier entry
            //    drops exactly the columns only it carried.
            //    That loss is permanent and silent: the discard runs under
            //    `_sync_apply_guard`, so nothing is re-broadcast, and the peer's
            //    watermark advances regardless.
            // 2. A genuine later WRITE still supersedes, through the one door
            //    that is allowed to say so: `noteRecordMutated` raises the
            //    tracked ordinal to `max(known, ordinalForParking)`.
            // 3. The assignment could also LOWER the tracked ordinal.
            //    `replaying` makes a RE-parked entry inherit its ORIGINAL
            //    position, so an unconditional write here can undo a
            //    supersession a later write had already recorded. Insert-if-
            //    absent cannot regress a tracked ordinal at all. (Not reachable
            //    today — an entry below `latest` is discarded before it can
            //    re-park — so this is defence, not a second observed bug.)
            //
            // Deleting the assignment outright would not be the fix AS THE CODE
            // STANDS, and that verdict is conditional on one thing:
            // `noteRecordMutated`'s early-return guard. Tracking only ever
            // starts here, and that guard returns early for an untracked key —
            // so with the assignment gone `isSuperseded` would be permanently
            // false and a parked merge replayed after a later DELETE would
            // resurrect the record (#1749's guard, gone). A variant that BOTH
            // deletes the park's assignment AND lets a write start tracking
            // (dropping that guard) also passes the suite; the shipped shape is
            // still preferred, because it never begins tracking a record that
            // never parked.
            let key = Self.recordKey(entry.table, entry.recordId)
            if latestArrivalOrdinal[key] == nil {
                latestArrivalOrdinal[key] = entry.arrivalOrdinal
            }
            return true
        }

        /// Remove and return the whole buffer for one replay pass.
        func takeDeferred() -> [DeferredMerge] {
            let entries = deferred
            deferred.removeAll(keepingCapacity: true)
            deferredBytes = 0
            return entries
        }

        /// Run `body` as the replay of `entry`, so anything it re-parks inherits
        /// `entry`'s original batch position.
        func replaying<T>(_ entry: DeferredMerge, _ body: () throws -> T) rethrows -> T {
            replayingArrivalOrdinal = entry.arrivalOrdinal
            defer { replayingArrivalOrdinal = nil }
            return try body()
        }

        func uniqueParticipatingColumns(_ db: Database, _ table: String) throws -> Set<String> {
            if let cached = uniqueColumnCache[table] { return cached }
            let columns = try ConflictResolver.uniqueParticipatingColumns(db, table)
            uniqueColumnCache[table] = columns
            return columns
        }

        /// The residue, shaped so it goes through `MergeResult.add` like any
        /// other outcome — and so it can only ever land in its own counters.
        func residue() -> ApplyOutcome {
            ApplyOutcome(
                conflicts: replayConflicts,
                keyCollisions: keyCollisions,
                schemaDrops: schemaDrops,
                supersededMerges: supersededMerges
            )
        }
    }

    /// Replay every merge a unique index refused, until it stops helping (#1737).
    ///
    /// Ordering-induced collisions are the dominant RECOVERABLE class: the row
    /// that vacates a slot routinely arrives after the row that wants it, because
    /// the host streams tables in creation order and rows in rowid order. Each
    /// pass re-applies the whole buffer; a row whose slot has since been vacated
    /// lands, which may in turn vacate a slot for another. When a pass frees
    /// nothing, no later pass can either, so it stops — and a hard pass cap
    /// bounds it regardless.
    ///
    /// Replaying is also a RE-ORDERING, and that half is not optional: an entry
    /// whose record was WRITTEN again later in the same batch is DISCARDED
    /// rather than applied, counted in `supersededMerges` and logged. Without
    /// that, a parked merge replayed after a later DELETE resurrects the record,
    /// and one replayed after a later UPDATE overwrites the newer values —
    /// silently, because the replay succeeds, and permanently, because
    /// `_sync_apply_guard` stops the corrected row being broadcast back.
    ///
    /// MUST run before `restoreJobStageSortIndex`: the replay needs the same
    /// suspended-index conditions the first pass had. MUST NOT run any DDL —
    /// the streamed producer's cursor may still be open on this connection, and
    /// `DROP INDEX`'s `OP_Destroy` guard is connection-wide.
    ///
    /// Never throws for a constraint outcome. Anything it does throw is the same
    /// class that already rolls the transaction back at HEAD.
    private static func drainDeferredMerges(_ db: Database, _ context: ApplyContext) throws {
        var passes = 0
        while context.hasDeferredWork, passes < ApplyContext.maxReplayPasses {
            passes += 1
            let before = context.deferredCount
            try replayDeferredMerges(db, context)
            if context.deferredCount >= before { break }
        }

        // Whatever survived the fixed point gets the full ladder: the reduced
        // SET clause, then the give-up rung. Nothing is left parked.
        context.isDraining = true
        try replayDeferredMerges(db, context)
        context.isDraining = false
    }

    /// One replay pass over the deferral buffer.
    private static func replayDeferredMerges(_ db: Database, _ context: ApplyContext) throws {
        for entry in context.takeDeferred() {
            // Deferral RE-ORDERS a change: this payload was change number
            // `entry.arrivalOrdinal`, and it is being applied after change
            // number N. That is a repair only while nothing else in the batch
            // touched the record in between; otherwise it is a rewrite of the
            // record's history that no counter would notice, because the replay
            // SUCCEEDS. Discard it instead — and say so.
            if context.isSuperseded(entry) {
                context.supersededMerges += 1
                // The message names the mechanism exactly, because it is the
                // only signal a discard produces. "Wrote" is literal: a later
                // change that wrote NOTHING — refused by NOT NULL/CHECK, an
                // unrecognised operation verb, an UPDATE carrying no fields, or
                // one that merely PARKED and then resolved to a rung of the
                // ladder that runs no statement — no longer reaches here at
                // all. See `noteRecordMutated` and `enqueueDeferredMerge`.
                let supersededAt = context.supersedingWriteOrdinal(entry) ?? entry.arrivalOrdinal
                logger.warning(
                    """
                    Deferred merge discarded: a later change in the same batch wrote this record — \
                    table=\(entry.table, privacy: .public) id=\(entry.recordId, privacy: .public) \
                    parkedAt=\(entry.arrivalOrdinal, privacy: .public) \
                    supersededAt=\(supersededAt, privacy: .public) \
                    from device=\(entry.change.deviceId, privacy: .public)
                    """
                )
                continue
            }

            guard let localRow = try getLocalRecord(
                db: db,
                tableName: entry.table,
                recordId: entry.recordId
            ) else {
                // The row we meant to merge into is gone — a hard DELETE removed
                // it (a soft delete leaves the row, and is caught by the
                // supersession check above). Re-inserting it belongs to the
                // insert builders, not here, so record the cause and move on.
                //
                // This is caught DELIBERATELY rather than allowed to reach
                // `applyUpdate`'s `missingLocalRecord` throw: that would land in
                // `skipped`, which the snapshot gate throws on inside the write
                // transaction. A replayed row must never be able to create a new
                // producer of a gate input.
                //
                // The cause is `supersededMerges`, NOT `keyCollisions`: no index
                // refused anything here. Counting a vanished record as a
                // constraint refusal is the same category error as counting one
                // as `skipped`, one counter further down.
                context.supersededMerges += 1
                logger.warning(
                    """
                    Deferred merge discarded: local record vanished during the batch — \
                    table=\(entry.table, privacy: .public) id=\(entry.recordId, privacy: .public) \
                    parkedAt=\(entry.arrivalOrdinal, privacy: .public)
                    """
                )
                continue
            }

            // `replaying` keeps the entry's ORIGINAL batch position on anything
            // this merge re-parks, so surviving a pass never promotes a change
            // to "newest for this record".
            let conflicts = try context.replaying(entry) {
                try fieldLevelMerge(
                    db: db,
                    table: entry.table,
                    recordId: entry.recordId,
                    localRow: localRow,
                    incomingFields: entry.incomingFields,
                    change: entry.change,
                    localDeviceId: entry.localDeviceId,
                    context: context
                )
            }
            // The change was already tallied when it first arrived, so only the
            // conflict rows written by THIS pass are new.
            context.replayConflicts += conflicts
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

    /// Apply a DELETE change — soft delete when the table has `deleted_at`, hard
    /// delete when it does not. The branch is decided by reading the schema, never
    /// by catching an error (see the comment at the statement itself for why).
    /// Fix #174: if the record has unsynced local UPDATEs, log an entry to `_conflict_log`
    /// so admins can see that local edits were trumped by a remote delete (delete-always-wins
    /// policy preserved for safety, but no longer silent).
    /// - Returns: whether a local row was actually removed. `false` means the
    ///   record was already gone, which is a successful delete that wrote
    ///   nothing — and a change that wrote nothing must not supersede a parked
    ///   merge. See `ApplyContext.noteRecordMutated`.
    @discardableResult
    private static func applyDelete(db: Database, change: IncomingChange, localDeviceId: String) throws -> Bool {
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

        // Soft delete when the table has a `deleted_at`, hard delete when it does not.
        //
        // Asking the schema is the only honest form of this question. This used to
        // be a soft-delete UPDATE wrapped in an UNTYPED catch whose comment asserted
        // the only possible cause was a missing `deleted_at` column. SQLite reports a
        // missing column as the GENERIC result code 1 (SQLITE_ERROR), indistinguishable
        // from a locked database, a trigger abort, a constraint failure or a disk I/O
        // error — so no catch here can tell "this table has no deleted_at" from "this
        // write genuinely failed", and the old one answered BOTH by hard-deleting the
        // row. On a table that DOES soft-delete, a transient SQLITE_BUSY was therefore
        // silently converted into permanent destruction of a record, inside a
        // transaction the rest of the sync layer treats as all-or-nothing.
        //
        // `pragma_table_info` is deliberately preferred over GRDB's `db.columns(in:)`:
        // the latter THROWS `noSuchTable` for a table this device does not have, while
        // the pragma returns zero rows and so preserves the previous behaviour for that
        // case (falls through to the DELETE, which raises "no such table" as before).
        let columns = try String.fetchAll(
            db,
            sql: "SELECT name FROM pragma_table_info(?)",
            arguments: [table]
        )

        if columns.contains("deleted_at") {
            try db.execute(
                sql: "UPDATE \(quotedTable(table)) SET deleted_at = ? WHERE id = ?",
                arguments: [change.timestamp, recordId]
            )
        } else {
            try db.execute(
                sql: "DELETE FROM \(quotedTable(table)) WHERE id = ?",
                arguments: [recordId]
            )
        }
        // `db.changesCount == 0` means the record was already gone locally, which is
        // fine — a delete we cannot apply because there is nothing to apply succeeded.
        // Read immediately: `changesCount` reports the LAST statement, and the
        // soft/hard delete above is the last statement on every path through here.
        return db.changesCount > 0
    }

    /// Apply an INSERT change — if record exists, field-level LWW merge.
    /// Returns conflict count.
    @discardableResult
    private static func applyInsert(
        db: Database,
        change: IncomingChange,
        localDeviceId: String,
        context: ApplyContext
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
            // A newer sender names columns this device does not have; keeping them
            // would fail at PREPARE time, which `OR IGNORE` cannot absorb, and
            // abort the whole transaction. See `filteredToLocalColumns`.
            let localFields = try filteredToLocalColumns(db: db, table: table, fields: recordDataFields)
            guard !localFields.isEmpty else { return 0 }

            let columns = localFields.keys.sorted()
            var placeholders: [String] = []
            var values: [String] = []
            for key in columns {
                if let present = localFields[key], let value = present {
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
            // `OR IGNORE` can write nothing, so ask rather than assume.
            if db.changesCount > 0 {
                context.noteRecordMutated(table: table, recordId: recordId)
            }
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
            localDeviceId: localDeviceId,
            context: context
        )
    }

    /// Apply an UPDATE change with changed_fields — field-level LWW merge.
    /// Returns conflict count.
    @discardableResult
    private static func applyUpdate(
        db: Database,
        change: IncomingChange,
        localDeviceId: String,
        context: ApplyContext
    ) throws -> Int {
        let table = change.tableName
        let recordId = change.recordId

        // Parse changed_fields
        let changedFields = parseJsonField(change.changedFields)

        if changedFields == nil && change.recordData != nil {
            // No changed_fields but has record_data — delegate to INSERT logic (full-record merge)
            return try applyInsert(
                db: db, change: change, localDeviceId: localDeviceId, context: context
            )
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
                // Same unknown-column filter as applyInsert's plain-INSERT path.
                // This is the sibling builder: the #196 NULL fix was applied here
                // only after it had been fixed once next door, so a fix that lands
                // in one of these two and not the other is a fix that is still broken.
                let localFields = try filteredToLocalColumns(db: db, table: table, fields: recordDataFields)
                guard !localFields.isEmpty else { return 0 }

                let columns = localFields.keys.sorted()
                var placeholders: [String] = []
                var values: [String] = []
                for key in columns {
                    if let present = localFields[key], let value = present {
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
                // `OR IGNORE` can write nothing, so ask rather than assume.
                if db.changesCount > 0 {
                    context.noteRecordMutated(table: table, recordId: recordId)
                }
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
            localDeviceId: localDeviceId,
            context: context
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
        localDeviceId: String,
        context: ApplyContext
    ) throws -> Int {
        // Filter BEFORE anything reads these keys. The merge `UPDATE` has no
        // conflict clause, so a column this device lacks is a prepare-time throw
        // that rolls the whole transaction back; and the conflict-logging loop
        // below subscripts `localRow[field]`, which is meaningless for a column
        // that does not exist here. See `filteredToLocalColumns`.
        let incomingFields = try filteredToLocalColumns(db: db, table: table, fields: incomingFields)

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
            // ATTEMPT 1 — exactly the statement HEAD built, run through the
            // classifier. At HEAD this `try` was bare, so a UNIQUE violation on
            // one row escaped `applyOneAtomically`'s `missingLocalRecord`-only
            // catch and rolled back the whole company snapshot (#1737).
            let statement = mergeUpdateStatement(
                table: table, mergedData: mergedData, recordId: recordId
            )
            // Captured INSIDE the closure so it is only ever read for a
            // statement that succeeded: after a refusal SQLite still reports the
            // PREVIOUS statement's row count.
            var rowsWritten = 0
            let refusal = try classifyingRowRefusal {
                try db.execute(sql: statement.sql, arguments: statement.arguments)
                rowsWritten = db.changesCount
            }

            switch refusal {
            case .none:
                if rowsWritten > 0 {
                    context.noteRecordMutated(table: table, recordId: recordId)
                }
                break   // fall through to conflict logging and the normal return

            case .schemaDrop:
                // NOT NULL / CHECK. A retry cannot change this device's schema
                // and neither can withholding a key column, so there is no
                // ladder to climb: leave the row exactly as it was, name the
                // cause, and NEVER rethrow.
                context.schemaDrops += 1
                logger.warning(
                    """
                    Merge UPDATE refused by a NOT NULL/CHECK constraint — row left unchanged: \
                    table=\(table, privacy: .public) id=\(recordId, privacy: .public) \
                    from device=\(change.deviceId, privacy: .public)
                    """
                )
                // Deliberately BEFORE `logConflicts`: nothing was written, so
                // there is no resolution to record. It is also what makes a
                // replay safe — no conflict row exists to be written twice.
                return 0

            case .keyCollision:
                // A DIFFERENT local row owns this key. On a batched path the row
                // holding the slot may itself move later in the same batch, so
                // park this merge and replay it after the batch. Nothing has
                // been written and nothing has been logged, so parking is free
                // and re-running is idempotent.
                //
                // Parking is also a RE-ORDERING, which is why the entry carries
                // its arrival position: the replay discards it if any later
                // change in the batch touched the same record. See
                // `ApplyContext.isSuperseded`.
                if context.canDefer {
                    let parked = context.enqueueDeferredMerge(DeferredMerge(
                        table: table,
                        recordId: recordId,
                        incomingFields: incomingFields,
                        change: change,
                        localDeviceId: localDeviceId,
                        arrivalOrdinal: context.ordinalForParking,
                        approximateBytes: approximatePayloadBytes(incomingFields, change)
                    ))
                    if parked { return 0 }
                    // Buffer cap hit. Falling through to the in-place ladder
                    // costs no additional memory and can still land the non-key
                    // columns, which is strictly better than recording the row
                    // as lost. Overflow degrades to "resolve now", never to
                    // "throw" — a throw here rolls back the whole snapshot.
                }

                return try resolveKeyCollisionInPlace(
                    db: db,
                    table: table,
                    recordId: recordId,
                    localRow: localRow,
                    mergedData: mergedData,
                    conflictEntries: conflictEntries,
                    localTimestamp: localTimestamp,
                    change: change,
                    localDeviceId: localDeviceId,
                    context: context
                )
            }
        }

        // Log all conflicts
        if !conflictEntries.isEmpty {
            try logConflicts(db: db, conflicts: conflictEntries)
        }

        return conflictEntries.count
    }

    /// Build the merge `UPDATE`'s SET clause and its bound arguments in ONE pass.
    ///
    /// Extracted verbatim so the reduced retry in `resolveKeyCollisionInPlace`
    /// re-runs this exact loop instead of re-deriving it. That is the whole
    /// point: they were previously derived independently, and they disagreed
    /// about what a NULL means — which aborted every sync carrying a null field
    /// with "SQLite error 21: wrong number of statement arguments" (#196).
    ///
    /// `mergedData` is `[String: String?]`, so a subscript yields `String??`:
    /// the OUTER level is "is the key present", the INNER level is "is the
    /// value SQL NULL". The old clause test matched the outer level, which
    /// is always `.some` here because the keys come from `mergedData.keys` —
    /// so the `= NULL` branch was unreachable and every field got a `?`.
    /// The old argument list unwrapped only the outer level and returned the
    /// inner optional, so `compactMap` silently dropped the NULL fields.
    /// Result: N placeholders, fewer than N arguments.
    ///
    /// A NULL is written as a SQL literal rather than a bound parameter, so
    /// a field with no value contributes a clause but no argument — which is
    /// exactly why the two must be built together. Never filter the returned
    /// clause and argument arrays by index: they have different lengths the
    /// moment any merged value is NULL.
    private static func mergeUpdateStatement(
        table: String,
        mergedData: [String: String?],
        recordId: String
    ) -> (sql: String, arguments: StatementArguments) {
        var setClauses: [String] = []
        var args: [any DatabaseValueConvertible] = []
        for key in mergedData.keys.sorted() {
            // `?? nil` flattens String?? to String?: key-absent and value-NULL
            // both collapse to nil, and both must produce a NULL literal.
            guard let value = mergedData[key] ?? nil else {
                setClauses.append("\"\(key)\" = NULL")
                continue
            }
            setClauses.append("\"\(key)\" = ?")
            args.append(value)
        }
        args.append(recordId)

        return (
            sql: """
                UPDATE \(quotedTable(table)) SET \(setClauses.joined(separator: ", ")) WHERE id = ?
                """,
            arguments: StatementArguments(args)
        )
    }

    /// Rough retained size of a parked entry, for bounding the buffer only.
    ///
    /// Counts BOTH halves of what `DeferredMerge` retains: the decoded field
    /// dictionary and the original change's JSON payloads. Counting only the
    /// dictionary would under-report by roughly half and let the 8 MB cap sail
    /// past the memory it exists to bound.
    private static func approximatePayloadBytes(
        _ fields: [String: String?],
        _ change: IncomingChange
    ) -> Int {
        let fieldBytes = fields.reduce(0) { total, entry in
            total + entry.key.utf8.count + (entry.value?.utf8.count ?? 0) + 16
        }
        return fieldBytes
            + (change.recordData?.utf8.count ?? 0)
            + (change.changedFields?.utf8.count ?? 0)
            + (change.oldValues?.utf8.count ?? 0)
            + 128
    }

    /// Attempts 2 and 3 of the merge ladder (#1737). NEVER rethrows a
    /// constraint refusal.
    ///
    /// **Attempt 2 — reduce the SET clause.** Withhold every column that
    /// participates in a unique index and re-run the statement, so the row's
    /// NON-key fields still land. Each withheld column is recorded in
    /// `_conflict_log` as a genuine `winner: "local"` resolution — with the REAL
    /// local value and the REAL local timestamp. (#1749 wrote `localTs: ""`
    /// here, which corrupts the admin review surface; `localTs` is a
    /// non-optional `String`, so an empty one compiles and fails only in the UI.)
    ///
    /// **Attempt 3 — give up, and never rethrow.** This rung is mandatory, not
    /// belt-and-braces. Two shapes in the live schema defeat attempt 2:
    ///
    /// - `job_stage_templates`, whose partial index is
    ///   `ON (is_default) WHERE is_default = 1 AND archived_at IS NULL`.
    ///   Withholding `is_default` still collides, because writing
    ///   `archived_at = NULL` alone moves the row INTO the index — and
    ///   `pragma_index_info` never reports `archived_at`.
    /// - `warehouse_walking_path_stops`, `UNIQUE(path_id, area_id) WHERE
    ///   deleted_at IS NULL`. An un-delete carries no index column in the SET
    ///   clause at all, so the reduced statement is byte-identical to the one
    ///   that just failed.
    ///
    /// Termination is therefore by the bounded ladder, not by a property of SQL
    /// that does not hold.
    private static func resolveKeyCollisionInPlace(
        db: Database,
        table: String,
        recordId: String,
        localRow: Row,
        mergedData: [String: String?],
        conflictEntries: [ConflictLogEntry],
        localTimestamp: String,
        change: IncomingChange,
        localDeviceId: String,
        context: ApplyContext
    ) throws -> Int {
        var entries = conflictEntries

        let uniqueColumns = try context.uniqueParticipatingColumns(db, table)
        // Intersect with what is actually in the SET clause. Withholding a
        // column that was never being written would produce a byte-identical
        // statement AND a bogus conflict row for a field nobody changed.
        let withheld = mergedData.keys.filter { uniqueColumns.contains($0) }.sorted()

        if !withheld.isEmpty {
            var reduced = mergedData
            for column in withheld {
                reduced.removeValue(forKey: column)
                entries.append(ConflictLogEntry(
                    tableName: table,
                    recordId: recordId,
                    fieldName: column,
                    localValue: stringifyValue(localRow[column] as DatabaseValue),
                    remoteValue: (mergedData[column] ?? nil) ?? "(NULL)",
                    winner: "local",
                    localDevice: localDeviceId,
                    remoteDevice: change.deviceId,
                    localTs: localTimestamp,
                    remoteTs: change.timestamp,
                    resolvedAt: currentTimestamp()
                ))
            }

            if reduced.isEmpty {
                // Everything the change carried was a key column. `SET` with no
                // assignments is a syntax error, and a prepare-time throw on the
                // snapshot path is a whole-company rollback — so skip the
                // statement entirely rather than building one.
                context.keyCollisions += 1
                logKeyCollision(table: table, recordId: recordId, change: change, withheld: withheld)
                if !entries.isEmpty { try logConflicts(db: db, conflicts: entries) }
                return entries.count
            }

            let statement = mergeUpdateStatement(
                table: table, mergedData: reduced, recordId: recordId
            )
            // See the sibling capture in `fieldLevelMerge`: only valid when the
            // statement did not throw.
            var rowsWritten = 0
            let refusal = try classifyingRowRefusal {
                try db.execute(sql: statement.sql, arguments: statement.arguments)
                rowsWritten = db.changesCount
            }

            switch refusal {
            case .none:
                // Non-key fields landed; the key columns did not. The row is
                // partially applied, and the cause is a key collision.
                //
                // Partially applied is still applied: a parked merge replayed
                // over this would overwrite values a LATER change just wrote.
                if rowsWritten > 0 {
                    context.noteRecordMutated(table: table, recordId: recordId)
                }
                context.keyCollisions += 1
                logKeyCollision(table: table, recordId: recordId, change: change, withheld: withheld)
                if !entries.isEmpty { try logConflicts(db: db, conflicts: entries) }
                return entries.count

            case .schemaDrop:
                context.schemaDrops += 1
                logger.warning(
                    """
                    Reduced merge UPDATE refused by a NOT NULL/CHECK constraint — row left \
                    unchanged: table=\(table, privacy: .public) id=\(recordId, privacy: .public)
                    """
                )
                return 0

            case .keyCollision:
                break   // fall through to attempt 3
            }
        }

        // ATTEMPT 3 — give up. The row is left exactly as it was.
        context.keyCollisions += 1
        logger.warning(
            """
            Merge UPDATE abandoned after the reduced retry also collided — row left unchanged: \
            table=\(table, privacy: .public) id=\(recordId, privacy: .public) \
            from device=\(change.deviceId, privacy: .public). A unique index this device holds \
            refuses the incoming values; a partial index's predicate column is the usual cause.
            """
        )
        return 0
    }

    private static func logKeyCollision(
        table: String,
        recordId: String,
        change: IncomingChange,
        withheld: [String]
    ) {
        logger.warning(
            """
            Merge UPDATE withheld \(withheld.count, privacy: .public) unique-key column(s) after a \
            UNIQUE refusal: table=\(table, privacy: .public) id=\(recordId, privacy: .public) \
            from device=\(change.deviceId, privacy: .public) — \
            \(withheld.joined(separator: ", "), privacy: .public)
            """
        )
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

    /// Drop payload fields naming a column this device's schema does not have.
    ///
    /// The sender decides the column set, not the receiver: the host streams a
    /// snapshot with `SELECT * FROM [table]` and emits a key for every non-blob
    /// column (`PeerManager.hostedSnapshotPage` / `jsonRecordDict`). Every
    /// statement builder below then names those keys verbatim. So when the
    /// SENDER is on a newer build, the receiver is handed a column it has never
    /// heard of, and SQLite rejects the statement at PREPARE time with
    /// `table X has no column named Y`.
    ///
    /// That is fatal on BOTH branches, which is what makes it worse than the
    /// constraint classes around it:
    ///
    /// - On the merge branch the `UPDATE` has no conflict clause, so it simply
    ///   throws.
    /// - On the insert branch `INSERT OR IGNORE` gives NO protection either.
    ///   ON CONFLICT resolution only applies to a statement that successfully
    ///   PREPARES; an unknown column name fails before any conflict handling
    ///   can run. This is a different failure mode from the NOT NULL / UNIQUE /
    ///   CHECK class, which `OR IGNORE` does absorb.
    ///
    /// Either way the throw escapes `applyOneAtomically`'s `missingLocalRecord`-
    /// only catch and rolls back the ENTIRE transaction — the whole company
    /// snapshot on a join, or the whole delta batch on ongoing sync. It is
    /// deterministic and identical on every retry, the same shape as #1723 and
    /// #1728, and the kill surface is already populated: migration history has
    /// added 90 columns via `add(column:)` plus 6 by raw `ALTER TABLE`, so one
    /// schema-adding migration of separation between two devices is enough.
    ///
    /// Mid-TestFlight-rollout is exactly this state — the shop Mac takes a build
    /// before a phone does, and iOS and macOS build numbers are cut separately.
    ///
    /// Dropping the unknown fields is the only available semantics: a receiver
    /// that lacks the column cannot store the value under any strategy, and it
    /// never had that data to begin with. Applying the rest of the row is
    /// strictly better than losing every row in the transaction. The dropped
    /// names are logged rather than swallowed so the divergence is diagnosable
    /// — and once that device takes the migration, an ordinary resync of the row
    /// carries the column normally.
    ///
    /// Returns the payload filtered to columns that exist locally.
    private static func filteredToLocalColumns(
        db: Database,
        table: String,
        fields: [String: String?]
    ) throws -> [String: String?] {
        let localColumns = Set(try db.columns(in: table).map(\.name))
        let unknown = fields.keys.filter { !localColumns.contains($0) }
        guard !unknown.isEmpty else { return fields }

        logger.warning(
            """
            Dropping \(unknown.count, privacy: .public) unknown column(s) from incoming \
            \(table, privacy: .public) row — this device's schema is older than the sender's: \
            \(unknown.sorted().joined(separator: ", "), privacy: .public)
            """
        )
        return fields.filter { localColumns.contains($0.key) }
    }
}
