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

    @Test("Schema version is 97")
    func testSchemaVersion() throws {
        #expect(AppDatabase.schemaVersion == 97)
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
}
