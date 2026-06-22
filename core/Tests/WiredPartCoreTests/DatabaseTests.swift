import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Database Migration Tests")
struct DatabaseTests {

    @Test("In-memory database opens and migrations run")
    func testInMemoryDatabaseOpens() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Verify the database is functional by checking a known table exists
        let tableExists = try db.writer.read { db in
            try db.tableExists("users")
        }
        #expect(tableExists)
    }

    @Test("All registered migrations apply successfully")
    func testAllMigrationsApply() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Check at least one representative table from each migration group
        let tables = [
            // Core foundation (000-008)
            "_change_log",       // 000
            "users",             // 001
            "parts",             // 002
            "jobs",              // 003
            "notebooks",         // 004
            "purchase_orders",   // 005
            "vehicles",          // 006
            "chat_channels",     // 007
            "_conflict_log",     // 008
            // People & scheduling (009-011)
            "certifications",    // 009
            "billing_periods",   // 010
            "pto_policies",      // 011
            // Fleet & tools (012-013)
            "job_trailers",      // 012
            "tool_depreciation_entries", // 013
            // Contacts & costs (014-017)
            "entity_contacts",   // 014
            "job_team_members",  // 015
            "companion_rules",   // 016
            "hat_permissions",   // 017
            // AI & profiles (018-019)
            "_text_history",     // 018
            "business_profiles", // 019
            // Warehouse & stock (020-021)
            "warehouse_locations", // 020
            // Notebooks & auth (022-024)
            // Pricing & suppliers (025-028)
            "pricing_tiers",     // 025
            // Forecasting (029-031)
            // JPO & staging (032-035)
            "staging_boxes",     // 035
            // Clock & chat (036-037)
            "message_attachments", // 037
            // Notebook hierarchy (038-039)
            "notebook_templates", // 039
            // Warehouse floor plans (040)
            "warehouse_floor_plans", // 040
            "warehouse_floor_features",
            "warehouse_storage_units",
            "warehouse_storage_levels",
            // Audit & compliance (041-042)
            "part_confidence",   // 041
            "break_records",     // 042
            // Payment & classification (043-045)
            "payment_records",   // 043
            // Scheduling & estimation (046-047)
            "estimation_questions", // 047
            "estimation_question_accuracy_reviews", // 082
            "warehouse_walking_paths", // 083
            "warehouse_walking_path_stops", // 083
            // Tools detail (048-050)
            "tool_checkouts",    // 048
            // Vehicle & trailer (051-053)
            "inspection_templates", // 053
            // Reports & office (054-055)
            "saved_reports",     // 054
            // AI conversations (056)
            "ai_conversation_messages", // 056
            // Wishlist & background tasks (057-058)
            "wishlist_items",    // 057
            "background_task_log", // 058
            "vehicle_location_logs", // 089
            "timesheet_correction_audits", // 103
            // Audit assignments & permissions (059-060)
        ]

        for table in tables {
            let exists = try db.writer.read { db in
                try db.tableExists(table)
            }
            #expect(exists, "Table \(table) should exist after migrations")
        }
    }


    @Test("Migration 097 creates part import audit session tables")
    func testMigration097CreatesPartImportAuditTables() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let tables = try db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('part_import_sessions', 'part_import_row_evidence') ORDER BY name")
        }
        #expect(tables == ["part_import_row_evidence", "part_import_sessions"])
    }

    @Test("Schema version is 105")
    func testSchemaVersion() throws {
        #expect(AppDatabase.schemaVersion == 105)
    }

    @Test("Migration 095 normalizes duplicate legacy stage sort orders and category maps")
    func testMigration095NormalizesDuplicateLegacyStageDataBeforeUniqueIndexes() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        var migrator = DatabaseMigrator()
        AppDatabase.registerMigrations(&migrator)
        try migrator.migrate(queue, upTo: "094_short_term_pipeline_category_override")

        try queue.write { db in
            try db.execute(sql: "INSERT INTO part_categories (name, description) VALUES ('Legacy Duplicate Category', 'migration fixture')")
            let categoryId = db.lastInsertedRowID
            let originalStageId = try Int64.fetchOne(db, sql: "SELECT id FROM job_stages WHERE sort_order = 1 ORDER BY id LIMIT 1")!
            try db.execute(sql: "INSERT INTO job_stages (name, sort_order, created_at) VALUES ('Legacy Duplicate Rough-in', 1, datetime('now'))")
            let duplicateStageId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO job_stage_category_map (stage_id, category_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [originalStageId, categoryId])
            try db.execute(sql: "INSERT INTO job_stage_category_map (stage_id, category_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [duplicateStageId, categoryId])
        }

        try migrator.migrate(queue)

        let result = try queue.read { db -> (sortOrders: [Int], mapStageIds: [Int64], templateMapCount: Int) in
            let sortOrders = try Int.fetchAll(db, sql: """
                SELECT sort_order FROM job_stages
                WHERE deleted_at IS NULL
                ORDER BY sort_order ASC, id ASC
                """)
            let mapStageIds = try Int64.fetchAll(db, sql: """
                SELECT m.stage_id
                FROM job_stage_category_map m
                JOIN part_categories c ON c.id = m.category_id
                WHERE c.name = 'Legacy Duplicate Category'
                ORDER BY m.id ASC
                """)
            let templateMapCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM job_stage_category_map
                WHERE template_id = (SELECT id FROM job_stage_templates WHERE is_default = 1 AND archived_at IS NULL)
                GROUP BY template_id, category_id
                HAVING COUNT(*) > 1
                """) ?? 0
            return (sortOrders, mapStageIds, templateMapCount)
        }

        #expect(result.sortOrders == Array(1...result.sortOrders.count))
        #expect(result.mapStageIds.count == 1)
        #expect(result.templateMapCount == 0)
    }

    @Test("Production backup and restore preserves critical beta records")
    func testProductionBackupRestorePreservesCriticalBetaRecords() throws {
        let fixture = try Self.makeCriticalBackupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let sourceSnapshot = try Self.criticalBackupSnapshot(at: fixture.databasePath)
        let backupPath = try #require(AppDatabase.backupDatabase(atPath: fixture.databasePath))
        let restoredPath = fixture.directory.appendingPathComponent("restored-production.sqlite").path

        try AppDatabase.restoreDatabase(from: backupPath, to: restoredPath)
        _ = try AppDatabase.openDatabase(atPath: restoredPath)

        let restoredSnapshot = try Self.criticalBackupSnapshot(at: restoredPath)
        #expect(restoredSnapshot == sourceSnapshot)
        #expect(restoredSnapshot.partName == "WEI-3986 Service Disconnect")
        #expect(restoredSnapshot.stockQuantity == 42)
        #expect(restoredSnapshot.stockMovementQuantity == 42)
        #expect(restoredSnapshot.jobMaterialQuantity == 3)
        #expect(restoredSnapshot.returnedMaterialQuantity == 1)
        #expect(restoredSnapshot.clockOutAnswer == "Panel labels complete")
        #expect(restoredSnapshot.jpoQuantityRequested == 5)
        #expect(restoredSnapshot.receivedQuantity == 5)
        #expect(restoredSnapshot.receivingItemQuantity == 5)
        #expect(restoredSnapshot.returnQuantity == 1)
        #expect(restoredSnapshot.savedReportName == "WEI-3986 Job Cost Rollup")
    }

    @Test("Migration 089 creates vehicle location logs table and latest-location indexes")
    func testMigration089VehicleLocationLogsIndexes() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let result = try db.writer.read { db -> (tableExists: Bool, columns: [String], indexes: [String]) in
            let tableExists = try db.tableExists("vehicle_location_logs")
            let columns = tableExists ? try db.columns(in: "vehicle_location_logs").map(\.name) : []
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('vehicle_location_logs')")
                .map { row in row["name"] as String }
            return (tableExists, columns, indexes)
        }

        #expect(result.tableExists, "vehicle_location_logs should be managed by migrations")
        #expect(result.columns.contains("vehicle_id"))
        #expect(result.columns.contains("user_id"))
        #expect(result.columns.contains("latitude"))
        #expect(result.columns.contains("longitude"))
        #expect(result.columns.contains("recorded_at"))
        #expect(result.columns.contains("deleted_at"))
        #expect(result.indexes.contains("idx_vll_vehicle"))
        #expect(result.indexes.contains("idx_vll_latest_active"))
        #expect(result.indexes.contains("idx_vll_recorded_at"))
    }

    @Test("Migration 088 adds fleet inspection dashboard lookup index")
    func testMigration088FleetInspectionDashboardLookupIndex() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let indexedColumns = try db.writer.read { db -> [String] in
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('inspection_records')")
            guard indexes.contains(where: { ($0["name"] as String) == "idx_ir_vehicle_performed_at" }) else {
                return []
            }

            return try Row.fetchAll(db, sql: "PRAGMA index_info('idx_ir_vehicle_performed_at')")
                .map { row in row["name"] as String }
        }

        #expect(indexedColumns == ["vehicle_id", "performed_at"])
    }

    @Test("Migration 082 adds structured estimation review columns")
    func testMigration082StructuredEstimationReviewColumns() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let columns = try db.writer.read { db in
            try db.columns(in: "estimation_reviews").map(\.name)
        }
        #expect(columns.contains("delay_factors"))
        #expect(columns.contains("on_track_status"))
        #expect(columns.contains("unresolved_question_count"))
        #expect(columns.contains("crew_feedback"))
        #expect(columns.contains("gc_rating"))
    }

    @Test("Migration 087 creates vehicle location log table and latest-location indexes")
    func testMigration087VehicleLocationLogsIndexes() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let result = try db.writer.read { db -> (tableExists: Bool, columns: [String], indexes: [String]) in
            let tableExists = try db.tableExists("vehicle_location_logs")
            let columns = tableExists ? try db.columns(in: "vehicle_location_logs").map(\.name) : []
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('vehicle_location_logs')")
                .map { row in row["name"] as String }
            return (tableExists, columns, indexes)
        }

        #expect(result.tableExists, "vehicle_location_logs should be managed by migrations")
        #expect(result.columns.contains("vehicle_id"))
        #expect(result.columns.contains("deleted_at"))
        #expect(result.indexes.contains("idx_vll_vehicle"))
        #expect(result.indexes.contains("idx_vll_latest_active"))
    }

    @Test("Migration 073 adds grid_rows and grid_cols to warehouse_floor_plans")
    func testMigration073FloorPlanGridDimensions() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let columns = try db.writer.read { db in
            try db.columns(in: "warehouse_floor_plans").map(\.name)
        }
        #expect(columns.contains("grid_rows"), "warehouse_floor_plans should have grid_rows after migration 073")
        #expect(columns.contains("grid_cols"), "warehouse_floor_plans should have grid_cols after migration 073")
    }

    @Test("Users table has correct columns")
    func testUsersTableSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "users").map(\.name)
        }

        let expectedColumns = [
            "id", "display_name", "email", "phone", "pin_hash",
            "default_truck_id", "emergency_contact_name", "emergency_contact_phone",
            "certification", "hire_date", "pay_rate", "is_active",
            "avatar_url", "deleted_at", "created_at", "updated_at",
        ]

        for col in expectedColumns {
            #expect(columns.contains(col), "users table should have column '\(col)'")
        }
    }

    @Test("Settings table has correct columns")
    func testSettingsTableSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "settings").map(\.name)
        }

        #expect(columns.contains("key"))
        #expect(columns.contains("value"))
        #expect(columns.contains("category"))
    }

    @Test("Change log table supports sync tracking")
    func testChangeLogSchema() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "_change_log").map(\.name)
        }

        let expected = ["id", "device_id", "table_name", "record_id", "operation",
                        "changed_fields", "old_values", "timestamp", "synced",
                        "sync_batch_id", "sequence"]

        for col in expected {
            #expect(columns.contains(col), "_change_log should have column '\(col)'")
        }
    }

    @Test("Sync infrastructure tables exist")
    func testSyncInfrastructure() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let syncTables = ["_conflict_log", "_vector_clock", "_device_registry"]
        for table in syncTables {
            let exists = try db.writer.read { db in
                try db.tableExists(table)
            }
            #expect(exists, "Sync table \(table) should exist")
        }
    }

    @Test("Company cost settings are seeded")
    func testCostSettingsSeeded() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let count = try db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM company_cost_settings")!
        }
        #expect(count == 6, "Should have 6 default cost settings (3 from migration 014 + 3 from migration 019)")
    }

    @Test("Parts table includes cost tracking columns from migration 014")
    func testPartsHasCostColumns() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "parts").map(\.name)
        }

        #expect(columns.contains("weighted_avg_cost"))
        #expect(columns.contains("custom_margin_percent"))
        #expect(columns.contains("cost_last_updated"))
    }

    @Test("Jobs table includes budget columns from migration 014")
    func testJobsHasBudgetColumns() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let columns = try db.writer.read { db in
            try db.columns(in: "jobs").map(\.name)
        }

        #expect(columns.contains("budget_limit"))
        #expect(columns.contains("budget_alert_percent"))
    }


    private struct CriticalBackupFixture {
        let directory: URL
        let databasePath: String
    }

    private struct CriticalBackupSnapshot: Equatable {
        let partName: String?
        let supplierName: String?
        let stockQuantity: Int
        let stockMovementQuantity: Int
        let jobName: String?
        let jobMaterialQuantity: Int
        let returnedMaterialQuantity: Int
        let laborHours: Double
        let clockOutAnswer: String?
        let jpoNumber: String?
        let jpoQuantityRequested: Int
        let purchaseOrderNumber: String?
        let receivedQuantity: Int
        let receivingSessionStatus: String?
        let receivingItemQuantity: Int
        let returnNumber: String?
        let returnQuantity: Int
        let orderHistoryStatus: String?
        let savedReportName: String?
        let reportAnnotation: String?
        let reportTemplateName: String?
        let billingPeriodNotes: String?
        let timesheetCorrectionReason: String?
        let auditSessionStatus: String?
        let auditEventType: String?
    }

    private static func makeCurrentCriticalBetaFixture() throws -> CriticalBackupFixture {
        try makeCriticalBackupFixture()
    }

    private static func currentCriticalFixtureSnapshot(at path: String) throws -> CriticalBackupSnapshot {
        try criticalBackupSnapshot(at: path)
    }

    private static func assertCurrentCriticalFixtureSnapshot(_ snapshot: CriticalBackupSnapshot) {
        #expect(snapshot.partName == "WEI-3986 Service Disconnect")
        #expect(snapshot.stockQuantity == 42)
        #expect(snapshot.jobMaterialQuantity == 3)
        #expect(snapshot.receivedQuantity == 5)
        #expect(snapshot.savedReportName == "WEI-3986 Job Cost Rollup")
    }

    private static func makeCriticalBackupFixture() throws -> CriticalBackupFixture {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("wei-3986-backup-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databasePath = directory.appendingPathComponent("production.sqlite").path
        let appDatabase = try AppDatabase.openDatabase(atPath: databasePath)
        try appDatabase.writer.write { db in
            try db.execute(sql: "INSERT INTO users (display_name, email, pin_hash) VALUES ('WEI-3986 Foreman', 'wei-3986@example.invalid', 'hash')")
            let userId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO suppliers (name, email, is_active) VALUES ('WEI-3986 Fixture Supply', 'supply@example.invalid', 1)")
            let supplierId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO part_categories (name, description) VALUES ('WEI-3986 Catalog', 'Backup fixture')")
            let categoryId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO parts (category_id, code, name, company_cost_price, company_markup_percent, min_stock_level, target_stock_level) VALUES (?, 'WEI-3986-PART', 'WEI-3986 Service Disconnect', 12.50, 20.0, 5, 25)", arguments: [categoryId])
            let partId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id) VALUES (?, 'warehouse', 1, 42, ?)", arguments: [partId, supplierId])
            try db.execute(sql: "INSERT INTO stock_movements (part_id, qty, to_location_type, to_location_id, supplier_id, movement_type, reason, reference_number, performed_by, unit_cost_at_move) VALUES (?, 42, 'warehouse', 1, ?, 'receive', 'Fixture stock receipt', 'WEI-3986-MOVE', ?, 12.50)", arguments: [partId, supplierId, userId])
            try db.execute(sql: "INSERT INTO jobs (job_number, job_name, customer_name, status, priority, job_type, lead_user_id, created_by, estimated_hours) VALUES ('JOB-WEI-3986', 'WEI-3986 Beta Restore Job', 'Backup Fixture Customer', 'active', 'high', 'commercial', ?, ?, 8.0)", arguments: [userId, userId])
            let jobId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO job_parts (job_id, part_id, qty_consumed, qty_returned, unit_cost_at_consume, consumed_by, notes) VALUES (?, ?, 3, 1, 12.50, ?, 'Material + return fixture')", arguments: [jobId, partId, userId])
            try db.execute(sql: "INSERT INTO labor_entries (user_id, job_id, clock_in, clock_out, regular_hours, status, notes) VALUES (?, ?, '2026-06-01T08:00:00Z', '2026-06-01T16:00:00Z', 8.0, 'approved', 'Labor fixture')", arguments: [userId, jobId])
            let laborEntryId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO clock_out_questions (question_text, answer_type, created_by) VALUES ('Anything unfinished?', 'text', ?)", arguments: [userId])
            let questionId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text) VALUES (?, ?, 'Panel labels complete')", arguments: [laborEntryId, questionId])
            try db.execute(sql: "INSERT INTO job_parts_orders (job_id, order_number, status, priority, requested_by, approved_by) VALUES (?, 'JPO-WEI-3986', 'approved', 'high', ?, ?)", arguments: [jobId, userId, userId])
            let jpoId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, qty_ordered, qty_received, suggested_supplier_id) VALUES (?, ?, 5, 5, 5, ?)", arguments: [jpoId, partId, supplierId])
            let jpoLineId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO purchase_orders (po_number, supplier_id, status, order_date, subtotal, total_cost, submitted_by) VALUES ('PO-WEI-3986', ?, 'ordered', '2026-06-01', 62.50, 62.50, ?)", arguments: [supplierId, userId])
            let poId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, qty_received, unit_cost, received_unit_cost, status, received_by) VALUES (?, ?, ?, 5, 5, 12.50, 12.50, 'received', ?)", arguments: [poId, jpoLineId, partId, userId])
            let poLineId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO receiving_sessions (po_id, started_by, mode, status, completed_at) VALUES (?, ?, 'packing_slip', 'completed', '2026-06-01T10:00:00Z')", arguments: [poId, userId])
            let receivingSessionId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, received_qty, actual_cost, scanned_at) VALUES (?, ?, 5, 5, 12.50, '2026-06-01T09:45:00Z')", arguments: [receivingSessionId, poLineId])
            try db.execute(sql: "INSERT INTO returns (return_number, return_type, po_id, supplier_id, job_id, status, reason, initiated_by) VALUES ('RET-WEI-3986', 'supplier', ?, ?, ?, 'approved', 'Overage return fixture', ?)", arguments: [poId, supplierId, jobId, userId])
            let returnId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO return_line_items (return_id, part_id, po_line_id, qty, condition, disposition, unit_cost) VALUES (?, ?, ?, 1, 'new', 'return_to_supplier', 12.50)", arguments: [returnId, partId, poLineId])
            try db.execute(sql: "INSERT INTO order_status_history (entity_type, entity_id, old_status, new_status, changed_by, notes) VALUES ('purchase_order', ?, 'draft', 'ordered', ?, 'Fixture history')", arguments: [poId, userId])
            try db.execute(sql: "INSERT INTO billing_periods (job_id, period_start, period_end, locked_by, notes) VALUES (?, '2026-06-01', '2026-06-07', ?, 'WEI-3986 pre-billing fixture')", arguments: [jobId, userId])
            try db.execute(sql: "INSERT INTO report_annotations (report_type, context_key, content, author_id) VALUES ('job_cost', 'JOB-WEI-3986', 'WEI-3986 report annotation', ?)", arguments: [userId])
            try db.execute(sql: "INSERT INTO report_templates (name, report_type, config_json, created_by) VALUES ('WEI-3986 Bookkeeper Template', 'bookkeeper', '{\"columns\":[\"labor\",\"materials\"]}', ?)", arguments: [userId])
            try db.execute(sql: "INSERT INTO saved_reports (name, report_type, columns_json, filters_json, created_by, is_shared, last_run_at) VALUES ('WEI-3986 Job Cost Rollup', 'job_cost', '[\"job\",\"materials\",\"labor\"]', '{\"job\":\"JOB-WEI-3986\"}', ?, 1, '2026-06-01T17:00:00Z')", arguments: [userId])
            try db.execute(sql: "INSERT INTO timesheet_correction_audits (labor_entry_id, employee_user_id, job_id, original_clock_in, original_clock_out, adjusted_clock_in, adjusted_clock_out, original_regular_hours, adjusted_regular_hours, reason, actor_user_id, approval_status) VALUES (?, ?, ?, '2026-06-01T08:00:00Z', '2026-06-01T16:00:00Z', '2026-06-01T08:15:00Z', '2026-06-01T16:15:00Z', 8.0, 8.0, 'WEI-3986 bookkeeper correction fixture', ?, 'approved')", arguments: [laborEntryId, userId, jobId, userId])
            try db.execute(sql: "INSERT INTO audit_sessions_v2 (session_type, started_by, status, parts_counted, discrepancies_found) VALUES ('count', ?, 'completed', 1, 0)", arguments: [userId])
            let auditSessionId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO audit_session_events (session_id, event_type, notes, recorded_by) VALUES (?, 'completed', 'WEI-3986 audit summary fixture', ?)", arguments: [auditSessionId, userId])
        }
        return CriticalBackupFixture(directory: directory, databasePath: databasePath)
    }

    private static func criticalBackupSnapshot(at path: String) throws -> CriticalBackupSnapshot {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
            CriticalBackupSnapshot(
                partName: try String.fetchOne(db, sql: "SELECT name FROM parts WHERE code = 'WEI-3986-PART'"),
                supplierName: try String.fetchOne(db, sql: "SELECT name FROM suppliers WHERE name = 'WEI-3986 Fixture Supply'"),
                stockQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM stock WHERE part_id = (SELECT id FROM parts WHERE code = 'WEI-3986-PART')") ?? 0,
                stockMovementQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM stock_movements WHERE reference_number = 'WEI-3986-MOVE'") ?? 0,
                jobName: try String.fetchOne(db, sql: "SELECT job_name FROM jobs WHERE job_number = 'JOB-WEI-3986'"),
                jobMaterialQuantity: try Int.fetchOne(db, sql: "SELECT qty_consumed FROM job_parts WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')") ?? 0,
                returnedMaterialQuantity: try Int.fetchOne(db, sql: "SELECT qty_returned FROM job_parts WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')") ?? 0,
                laborHours: try Double.fetchOne(db, sql: "SELECT regular_hours FROM labor_entries WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')") ?? 0,
                clockOutAnswer: try String.fetchOne(db, sql: "SELECT answer_text FROM clock_out_responses WHERE labor_entry_id = (SELECT id FROM labor_entries WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986'))"),
                jpoNumber: try String.fetchOne(db, sql: "SELECT order_number FROM job_parts_orders WHERE order_number = 'JPO-WEI-3986'"),
                jpoQuantityRequested: try Int.fetchOne(db, sql: "SELECT qty_requested FROM jpo_line_items WHERE jpo_id = (SELECT id FROM job_parts_orders WHERE order_number = 'JPO-WEI-3986')") ?? 0,
                purchaseOrderNumber: try String.fetchOne(db, sql: "SELECT po_number FROM purchase_orders WHERE po_number = 'PO-WEI-3986'"),
                receivedQuantity: try Int.fetchOne(db, sql: "SELECT qty_received FROM po_line_items WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')") ?? 0,
                receivingSessionStatus: try String.fetchOne(db, sql: "SELECT status FROM receiving_sessions WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')"),
                receivingItemQuantity: try Int.fetchOne(db, sql: "SELECT received_qty FROM receiving_session_items WHERE session_id = (SELECT id FROM receiving_sessions WHERE po_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986'))") ?? 0,
                returnNumber: try String.fetchOne(db, sql: "SELECT return_number FROM returns WHERE return_number = 'RET-WEI-3986'"),
                returnQuantity: try Int.fetchOne(db, sql: "SELECT qty FROM return_line_items WHERE return_id = (SELECT id FROM returns WHERE return_number = 'RET-WEI-3986')") ?? 0,
                orderHistoryStatus: try String.fetchOne(db, sql: "SELECT new_status FROM order_status_history WHERE entity_type = 'purchase_order' AND entity_id = (SELECT id FROM purchase_orders WHERE po_number = 'PO-WEI-3986')"),
                savedReportName: try String.fetchOne(db, sql: "SELECT name FROM saved_reports WHERE name = 'WEI-3986 Job Cost Rollup'"),
                reportAnnotation: try String.fetchOne(db, sql: "SELECT content FROM report_annotations WHERE context_key = 'JOB-WEI-3986'"),
                reportTemplateName: try String.fetchOne(db, sql: "SELECT name FROM report_templates WHERE name = 'WEI-3986 Bookkeeper Template'"),
                billingPeriodNotes: try String.fetchOne(db, sql: "SELECT notes FROM billing_periods WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986')"),
                timesheetCorrectionReason: try String.fetchOne(db, sql: "SELECT reason FROM timesheet_correction_audits WHERE labor_entry_id = (SELECT id FROM labor_entries WHERE job_id = (SELECT id FROM jobs WHERE job_number = 'JOB-WEI-3986'))"),
                auditSessionStatus: try String.fetchOne(db, sql: "SELECT status FROM audit_sessions_v2 WHERE session_type = 'count' AND parts_counted = 1"),
                auditEventType: try String.fetchOne(db, sql: "SELECT event_type FROM audit_session_events WHERE notes = 'WEI-3986 audit summary fixture'")
            )
        }
    }
}
