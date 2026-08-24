import Foundation
import GRDB

/// On-device verification that this database can actually replicate.
///
/// ## Why this exists (#1780)
///
/// `ConflictResolver.allowedSyncTables` is a **live** set, but the change-tracking
/// triggers that make those tables replicate are created **only inside numbered
/// migrations** — `AppDatabase+Migrations.swift:6061` loops the live allowlist at
/// the moment *that device* runs *that* migration, and `:6229` deliberately uses a
/// FROZEN copy because "a migration must not read the live allowlist — it drifts".
///
/// So a table added to the allowlist *after* a device ran those migrations gets no
/// triggers on that device, its writes never enter `_change_log`, and it silently
/// never syncs. That is precisely how 22 tables went missing before 2026-08-02;
/// migration 121 patched those 22, not the mechanism that produces them.
///
/// `SyncTableClassificationTests` cannot catch it: it runs against a freshly
/// migrated database, so it proves a clean install is correct and says nothing
/// about a device that accumulated migrations over months. It also spot-checks
/// five tables, not the full set. **The invariant was verified at build time and
/// never on the device where it matters.**
///
/// ## Why it must not depend on sync
///
/// `device_logs` is itself in `allowedSyncTables` and replicates over sync, so when
/// sync is down the logs cannot reach anyone (trap #9 in tracker #1681). Everything
/// here is therefore a plain local read, renderable to text and carried out of band.
public enum SyncSelfCheck {

    /// The three operations every synced table must log.
    static let trackedOperations = ["insert", "update", "delete"]

    // MARK: - Result types

    /// One table's trigger state. `missingOperations` empty means healthy.
    public struct TableTriggerState: Sendable, Equatable {
        public let table: String
        public let missingOperations: [String]

        public var isHealthy: Bool { missingOperations.isEmpty }
    }

    /// The outcome of a trigger audit.
    ///
    /// `checkedTables` is reported deliberately and prominently: a findings count
    /// of zero is meaningless without its denominator. "0 tables missing triggers"
    /// over 0 tables checked is the exact shape of a blind pass, and this project
    /// has already shipped one of those on the Dependabot surface (#1777).
    public struct TriggerAudit: Sendable, Equatable {
        /// Tables in `allowedSyncTables` that are eligible and were examined.
        public let checkedTables: Int
        /// Allowlist entries skipped because they are not present in this database.
        public let absentTables: [String]
        /// Allowlist entries skipped because they have no `id` column, mirroring
        /// the migration's own guard — such tables cannot participate in sync.
        public let idlessTables: [String]
        /// Only the unhealthy tables, sorted for stable output.
        public let tablesMissingTriggers: [TableTriggerState]

        public var isHealthy: Bool { tablesMissingTriggers.isEmpty }

        /// Total individual triggers absent across all tables.
        public var missingTriggerCount: Int {
            tablesMissingTriggers.reduce(0) { $0 + $1.missingOperations.count }
        }
    }

    // MARK: - Audit

    /// Verify every eligible allowlisted table has all three change-tracking
    /// triggers. Read-only.
    ///
    /// Eligibility mirrors the migration's guards exactly — skip `_`-prefixed
    /// internal tables, skip tables absent from this database, skip tables with no
    /// `id` column — so a table this reports as healthy is one the migration would
    /// also have handled. Diverging here would produce false alarms that erode
    /// trust in the check.
    public static func auditTriggers(_ db: Database) throws -> TriggerAudit {
        let existingTables = try Set(String.fetchAll(
            db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
        ))
        let existingTriggers = try Set(String.fetchAll(
            db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'"
        ))

        var checked = 0
        var absent: [String] = []
        var idless: [String] = []
        var unhealthy: [TableTriggerState] = []

        for table in ConflictResolver.allowedSyncTables.sorted() {
            guard !table.hasPrefix("_") else { continue }
            guard existingTables.contains(table) else {
                absent.append(table)
                continue
            }
            let columns = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]
            )
            guard columns.contains("id") else {
                idless.append(table)
                continue
            }

            checked += 1
            let missing = trackedOperations.filter { op in
                !existingTriggers.contains(triggerName(table: table, operation: op))
            }
            if !missing.isEmpty {
                unhealthy.append(TableTriggerState(table: table, missingOperations: missing))
            }
        }

        return TriggerAudit(
            checkedTables: checked,
            absentTables: absent,
            idlessTables: idless,
            tablesMissingTriggers: unhealthy
        )
    }

    // MARK: - Repair

    /// Create any missing change-tracking triggers, and return the trigger names
    /// created. Idempotent — `CREATE TRIGGER IF NOT EXISTS`, identical SQL to the
    /// migrations, so running it twice is a no-op.
    ///
    /// - Important: this repairs **future** writes only. A table that never had
    ///   triggers also has no `_change_log` history, so its pre-existing rows still
    ///   will not replicate until they are backfilled. The migrations pair trigger
    ///   creation with a bootstrap backfill for exactly this reason. Backfilling is
    ///   deliberately NOT done here: it can be very large, it is a data decision
    ///   rather than a repair, and doing it silently inside a diagnostic would be
    ///   the kind of hidden side effect this codebase has been bitten by. Report
    ///   the missing triggers, repair them, and let the backfill be an explicit
    ///   choice.
    @discardableResult
    public static func reconcileMissingTriggers(_ db: Database) throws -> [String] {
        let audit = try auditTriggers(db)
        var created: [String] = []

        for state in audit.tablesMissingTriggers {
            for op in state.missingOperations {
                let sqlOperation = op.uppercased()
                let rowReference = (sqlOperation == "DELETE") ? "OLD" : "NEW"
                let name = triggerName(table: state.table, operation: op)
                // Migration 126 replaced device_logs' original unconditional
                // triggers with this severity guard. Recreating the generic
                // shape would make verbose logs replicate again, even though
                // the audit would call the trigger healthy by name alone.
                let deviceLogSeverityGuard = state.table == "device_logs"
                    ? "\n     AND COALESCE(\(rowReference).severity, 30) >= \(DeviceLogService.replicationMinSeverity)"
                    : ""
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(name)
                    AFTER \(sqlOperation) ON [\(state.table)]
                    WHEN (SELECT COUNT(*) FROM _sync_apply_guard) = 0\(deviceLogSeverityGuard)
                    BEGIN
                        INSERT INTO _change_log (device_id, table_name, record_id, operation)
                        VALUES ('', '\(state.table)', \(rowReference).id, '\(sqlOperation)');
                    END
                    """)
                created.append(name)
            }
        }
        return created
    }

    // MARK: - Rendering

    /// A human-readable report, safe to share out of band.
    ///
    /// Contains table names and counts only — never row contents. `device_logs`
    /// bodies and business data are deliberately excluded: WEI-6938 is a live
    /// incident in this org caused by credential-like material reaching a place it
    /// should not, and a diagnostic the user is encouraged to send onward is
    /// exactly the wrong place to widen that surface.
    public static func renderTriggerAudit(_ audit: TriggerAudit) -> String {
        var lines: [String] = []
        lines.append("SYNC TRIGGER AUDIT")
        lines.append("  allowlisted tables : \(ConflictResolver.allowedSyncTables.count)")
        lines.append("  checked on device  : \(audit.checkedTables)")
        lines.append("  absent from DB     : \(audit.absentTables.count)")
        lines.append("  skipped (no id col): \(audit.idlessTables.count)")

        if audit.isHealthy {
            lines.append("  RESULT: OK — all \(audit.checkedTables) checked tables have all 3 triggers")
            return lines.joined(separator: "\n")
        }

        lines.append("  RESULT: \(audit.tablesMissingTriggers.count) TABLE(S) CANNOT REPLICATE"
                     + " — \(audit.missingTriggerCount) trigger(s) missing")
        for state in audit.tablesMissingTriggers {
            lines.append("    - \(state.table): missing \(state.missingOperations.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    static func triggerName(table: String, operation: String) -> String {
        "trg_sync_\(table)_\(operation.lowercased())"
    }
}
